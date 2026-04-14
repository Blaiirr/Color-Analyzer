# Architecture — Color Analyzer 色彩分析仪

## Data Flow

```
User action
(drag / drop / paste / file picker / history tap)
         │
         ▼
  ColorAnalyzer.analyze(image:)          ← ObservableObject
         │  runs on DispatchQueue.global
         │
         ├── samplePixels()              200×200 grid, RGBA → HSB + luminance
         ├── buildHistogram()            256-bin luminance histogram
         ├── kMeansClustering()          K-Means++ in perceptual HSB space
         │       ├── initCentroidsHSB()  probability-weighted initialization
         │       ├── hsbDist()           saturation-modulated hue metric
         │       └── updateCentroidsHSB() circular mean for hue
         └── buildColorPoints()          hue/sat grid → 200 ColorPoints
                          │
                          ▼  DispatchQueue.main
              @Published var result: AnalysisResult?
                          │
          ┌───────────────┼─────────────────┐
          │               │                 │
          ▼               ▼                 ▼
   HistoryStore      LeftPanel          RightPanel
   (onReceive)    ImagePreviewCard    ColorStripCard
                  HistogramCard       ColorWheelPickerCard
                                      HueWheelCard
```

---

## File Map

| File | Responsibility |
|------|---------------|
| `ColorAnalyzer.swift` | Data models (`DominantColor`, `ColorPoint`, `LuminanceHistogram`, `AnalysisResult`) + the analysis engine (`ColorAnalyzer: ObservableObject`) |
| `ContentView.swift` | Three-pane shell (`HSplitView`), `HistoryStore`, `HistorySidebar`, `LeftPanel`, `ImageDropZone`, `ImagePreviewCard`, `HistogramCard`, `HistogramView`, `ZoneStat` |
| `RightPanel.swift` | `RightPanel`, `ColorStripCard`, `ColorChip`, `ColorWheelPickerCard`, `InteractiveColorWheelView`, `SBSquareView`, `HueWheelCard`, `WheelColorChip` |
| `PDFExporter.swift` | Reserved stub |

---

## Layout — Three-Pane `HSplitView`

```
┌──────┬─────────────────────┬──────────────────────────────────────┐
│      │                     │                                      │
│ 最近 │   色彩分析仪         │   分析结果                           │
│      │                     │                                      │
│  72  │  ImageDropZone      │  ColorStripCard  (28 px strip)       │
│  px  │  ImagePreviewCard   │                                      │
│      │  HistogramCard      │  ColorWheelPickerCard  ← main view   │
│ side │    ├ stats header   │    ├ Segmented Picker (全色/主色)      │
│ bar  │    ├ HistogramView  │    ├ InteractiveColorWheelView        │
│      │    └ ZoneStat ×3    │    └ SBSquareView                    │
│      │                     │                                      │
│      │  min 320, max 440   │  HueWheelCard                        │
│      │                     │  min 600                             │
└──────┴─────────────────────┴──────────────────────────────────────┘
```

---

## Key Components

### `ColorAnalyzer` (ObservableObject)
- Three `@Published` properties: `result`, `isAnalyzing`, `errorMessage`
- `analyze(image:)` — kicks off background pipeline, publishes `AnalysisResult` on main
- `restore(result:)` — sets result directly without re-running the pipeline; called by the history sidebar so thumbnails load instantly
- `reanalyze()` — re-runs analysis on the last image (used internally)

### `AnalysisResult`
- Immutable value type carrying everything needed by all views
- `let id = UUID()` — stable identity used by `HistoryStore` for deduplication

### `HistoryStore` (ObservableObject)
- Ring buffer of the last 10 `AnalysisResult` values
- **Move-to-front deduplication**: `add(_:)` checks `entries.firstIndex(where: { $0.result.id == result.id })` — if found anywhere in the list, the existing entry is removed and re-inserted at index 0. If not found, a new entry is prepended and the tail is trimmed to 10
- Stores pre-scaled 56×56 `NSImage` thumbnails to avoid repeated scaling during scroll
- Subscribed via `.onReceive(analyzer.$result)` on `ContentView` — fires on every new result, skips history restores automatically because `restore()` re-publishes an existing `id`

### `HistogramView`
- Uses `logNormalizedBins()`: `log(1+count) / log(1+maxCount)` — compresses dominant spikes so minority tones remain visible
- `onContinuousHover` tracks cursor X position → displays V% tooltip as a capsule label
- Two dashed zone dividers at 1/3 and 2/3 width

### `ColorWheelPickerCard`
- `@State private var dominantOnly: Bool` — drives the `Picker(.segmented)` with tags `false` (全色显示) and `true` (主色模式)
- Passes `dominantOnly` down to `InteractiveColorWheelView` and `SBSquareView`

### `InteractiveColorWheelView`
- **全色显示 (dominantOnly = false)**: renders up to 200 `ColorPoint` dots on the polar wheel, sized by `proportion`; also renders dominant color tick marks on the outer ring
- **主色模式 (dominantOnly = true)**: renders only the dominant color markers, clustered more cleanly with no scatter noise
- `onContinuousHover` on the outer ring drives `selectedHue` → passed back to `SBSquareView` for the S×B detail square
- `HueNavState` observes keyboard `←` / `→` to cycle through dominant hues

### `SBSquareView`
- Renders an HSB gradient background (hue fixed to `selectedHue`)
- **全色显示**: up to 60 scatter `ColorPoint` dots filtered by proximity to `selectedHue` (±20°)
- **主色模式**: up to 8 dominant color ring markers (3-ring bullseye) positioned at `(saturation × width, (1−brightness) × height)`

### `ColorChip` / `WheelColorChip`
- Click: copies HEX to `NSPasteboard.general`, shows a `✓` checkmark for 1.5 s (via `DispatchQueue.main.asyncAfter`)
- Right-click context menu: copies HEX, RGB, or HSB string

---

## Threading Model

| Thread | Work |
|--------|------|
| `DispatchQueue.global(.userInitiated)` | Pixel sampling, histogram build, K-Means++ (all ~100 ms combined) |
| `DispatchQueue.main` | All `@Published` mutations, all SwiftUI view updates |

`[weak self]` is captured in the background closure to prevent `ColorAnalyzer` from being retained past its owner's lifetime.

---

## Design Decisions

### 1 · `onReceive` instead of `onChange`
`onChange(of:)` requires the observed value to conform to `Equatable`. `NSImage` is an Objective-C class with no `Equatable` conformance, so using it with `onChange` produces a compile-time error. Switching to `.onReceive(analyzer.$result)` subscribes directly to the Combine `Publisher` stream, which has no equality requirement.

### 2 · `restore()` vs `analyze()` for history
When a user taps a history thumbnail, the app should jump instantly — not re-run 100 ms of clustering on the same pixels. `restore(result:)` just writes the already-computed `AnalysisResult` to `@Published var result`. Because the `id` is the same UUID, `HistoryStore.add()` performs a move-to-front rather than inserting a new entry, keeping the list stable.

### 3 · UUID on `AnalysisResult`
`AnalysisResult` is a value type (`struct`). Struct identity by value would require deep equality comparison across all fields including `NSImage` — which has no `Equatable`. A `let id = UUID()` generated once at creation gives each result stable identity without touching `NSImage`.

### 4 · Logarithmic Histogram
Linear normalization: `count / maxCount`. A white-background photo has thousands of pixels in the "near-white" bins and near-zero counts everywhere else — the chart shows one spike and a flat floor. Log normalization: `log(1+count) / log(1+maxCount)` compresses the spike by the same logarithm that lifts the floor, making all zones readable simultaneously without any manual threshold tuning.

### 5 · Perceptual HSB Distance vs CIE Lab
CIE Lab is the academic standard for perceptual uniformity but requires an RGB→XYZ→Lab conversion matrix and introduces a dependency on the viewing illuminant. The custom metric `Δhue² × (1 + avgSat × 4) + ΔSat² + ΔBri² × 0.5` achieves the same practical goal — saturated hues are treated as farther apart than grays of the same hue difference — with a single arithmetic expression and zero external dependencies. For the use case of dominant-color extraction (not color-difference measurement), this approximation is sufficient.

### 6 · Two-Mode Wheel (Segmented Picker)
Early versions had a "spray gun deduplication" toggle that tried to merge perceptually similar scatter points before rendering. In practice the threshold was hard to tune — too aggressive and vivid clusters merged; too lenient and the wheel was still noisy. The current two-mode design sidesteps the problem: 全色显示 renders raw scatter (deliberate noise, useful for seeing the full color distribution), and 主色模式 renders only the K-Means++ centroids (clean, useful for palette reference). The user chooses the trade-off explicitly.

---

## Error History (for reference)

| Error | Root cause | Fix |
|-------|-----------|-----|
| `onChange(of:)` compile error | `AnalysisResult` contains `NSImage`, which has no `Equatable` conformance | Switch to `.onReceive(analyzer.$result)` |
| History re-adding on restore | `HistoryStore.add()` only checked `entries.first`, not all entries | Use `firstIndex(where:)` + move-to-front for any position |
| Histogram spike unreadable | Linear normalization lets the max bin dominate the chart scale | Replace with log normalization: `log(1+count) / log(1+max)` |
| App icon not appearing | `AppIcon.iconset` (iconutil format) referenced as a resource; no `AppIcon.appiconset` or `Contents.json` for Asset Catalog; `ASSETCATALOG_COMPILER_APPICON_NAME` not set | Create `AppIcon.appiconset/Contents.json`, add build setting, remove old iconset from Resources build phase |
| `ConvertIconsetFile` build error | `AppIcon.iconset` was still in the Xcode Resources build phase; Xcode tried to run `iconutil` on it | Remove all three references (PBXBuildFile, PBXFileReference, PBXResourcesBuildPhase) from `project.pbxproj` |
