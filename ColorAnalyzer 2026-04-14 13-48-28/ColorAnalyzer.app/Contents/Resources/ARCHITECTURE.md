# Architecture

## Overview

Color Analyzer follows a strict **unidirectional data flow**: the user loads an image → the analysis engine produces an immutable result value → SwiftUI renders from that value. No view can mutate shared state directly; all mutations go through the `ColorAnalyzer` observable object.

```
User action (drop / paste / history tap)
        │
        ▼
ColorAnalyzer.analyze(image:)
        │   runs on DispatchQueue.global(qos: .userInitiated)
        ├── samplePixels()        200×200 downsample → HSB + luminance tuples
        ├── buildHistogram()      256-bin luminance histogram
        ├── kMeansClustering()    K-Means++ in perceptual HSB space, k = 16
        └── buildColorPoints()   36×10 HSB grid → scatter data for hue wheel
        │
        ▼  DispatchQueue.main.async
@Published result: AnalysisResult?   (immutable struct)
        │
        ▼
ContentView → LeftPanel + RightPanel   (SwiftUI diffing, only changed subtrees re-render)
```

---

## File Map

```
ColorAnalyzer/
├── ColorAnalyzer.swift
│     Data models (DominantColor, ColorPoint, AnalysisResult, LuminanceHistogram)
│     Analysis engine (ColorAnalyzer: ObservableObject)
│     All algorithm code: sampling, histogram, K-Means++, scatter aggregation
│
├── ContentView.swift
│     HistoryStore + NSImage thumbnail helper
│     ContentView — 3-pane HSplitView, Cmd+V paste, onChange history recording
│     HistorySidebar — thumbnail strip, click to re-analyze
│     LeftPanel — drop zone (full / compact), image preview, histogram card
│     ImageDropZone — drag-and-drop + file picker
│     HistogramCard / HistogramView / ZoneStat — luminance visualization
│
├── RightPanel.swift
│     RightPanel — scroll container, empty state
│     OverviewStatsRow — resolution + color count summary
│     ColorStripCard + ColorChip — proportional color strip, click-to-copy chips
│     HueWheelCard — scatter hue wheel + all-colors S×V overview
│     HueWheelView — polar scatter, hover tooltip
│     AllColorsSBView — static S×B grid of all dominant colors
│     ColorWheelPickerCard — interactive wheel + spray-gun mode + chip legend
│     InteractiveColorWheelView — draggable hue ring + filtered SB square
│     SBSquareView — S×B gradient square filtered by selected hue ±22°
│     HueNavState — keyboard ←→ navigation (NSEvent monitor, ObservableObject)
│     WheelColorChip — chip in the horizontal legend, click-to-copy
│
└── PDFExporter.swift
      Stub file. PDF export was removed; kept to avoid breaking the Xcode target.
```

---

## Key Components

### `ColorAnalyzer` (ObservableObject — single source of truth)

Owns all mutable analysis state. Three `@Published` properties drive the entire UI:

| Property | Type | Purpose |
|----------|------|---------|
| `result` | `AnalysisResult?` | `nil` while idle or analyzing; set on completion |
| `isAnalyzing` | `Bool` | Drives loading spinner in the drop zone |
| `errorMessage` | `String?` | Surface-level error message |

Analysis runs off the main thread; the result is committed back via `DispatchQueue.main.async`. This keeps the SwiftUI render loop running at 60 fps during the ~100 ms clustering step.

### `HistoryStore` (ObservableObject — app-level, owned by ContentView)

Ring buffer (max 10) of `NSImage` references. Thumbnails (56×56) are pre-scaled at insert time so the sidebar draws cheaply — no image scaling on each render cycle.

Populated via `ContentView.onChange(of: analyzer.result)` — no direct coupling between `HistoryStore` and `ColorAnalyzer`.

### `AnalysisResult` (immutable struct — the "rendered frame")

Snapshot of one complete analysis run. All child views receive this value type; they hold their own copy and cannot accidentally mutate shared state. This makes the rendering path purely functional.

### `DominantColor` (value type)

Cluster centroid. Carries: raw pixel `proportion`, `hue`/`saturation`/`brightness` (HSB, 0–1), and an `NSColor` reference for rendering. The `proportion` is always the true pixel ratio; ranking uplift is applied only to the sort order, never to this value.

### `ColorPoint` (value type)

Aggregated scatter point for the hue wheel. Pixels are binned into a 36 × 10 HSB grid (36 hue bins × 10 saturation bins); up to 200 points with `proportion > 0.001` are forwarded to the view layer.

### `HueNavState` (reference type — keyboard event owner)

Holds the `NSEvent` local monitor reference for ←/→ keyboard navigation. Must be a class (`ObservableObject`) because closures passed to `NSEvent.addLocalMonitorForEvents` need to capture `self` by reference — struct captures would copy the value. Stored as `@StateObject` in `ColorWheelPickerCard`.

---

## Data Flow Detail

```
User drags image onto drop zone
  └── ImageDropZone.handleDrop()
        └── analyzer.analyze(image:)         [main thread call]
              └── DispatchQueue.global {
                    samplePixels()            [background]
                    buildHistogram()          [background]
                    kMeansClustering()        [background — K-Means++]
                    buildColorPoints()        [background]
                    DispatchQueue.main {
                      self.result = AnalysisResult(...)   [@Published → SwiftUI diff]
                      self.isAnalyzing = false
                    }
                  }

SwiftUI diffing fires:
  ContentView.onChange(of: result) → history.add(result.image)
  LeftPanel sees result != nil → switches to compact layout
  RightPanel sees result != nil → renders all cards
```

**Interactive hue selection (zero re-analysis):**
```
User drags hue ring
  └── DragGesture.onChanged → selectedHue = angle   [@State, local to ColorWheelPickerCard]
        └── SBSquareView.filtered recomputes inline
              └── SwiftUI re-renders only SBSquareView + WheelColorChip opacities
```

---

## Threading Model

| Work | Thread | Rationale |
|------|--------|-----------|
| Pixel sampling | `DispatchQueue.global` | CPU-bound, ~5 ms |
| K-Means iterations | `DispatchQueue.global` | CPU-bound, ~80 ms |
| UI state updates | `DispatchQueue.main` | SwiftUI requirement |
| Hue ring drag | Main (gesture callback) | < 1 ms, safe to block |
| Keyboard navigation | `DispatchQueue.main` (dispatched from NSEvent) | `@Published` mutation requires main |

---

## Design Decisions

**Why HSB clustering instead of CIE Lab?**

Lab conversion requires RGB → linear RGB (gamma correction) → XYZ → Lab — a non-trivial pipeline with no standard Swift implementation outside of Core Image. The custom HSB distance achieves the key perceptual property (hue differences amplified by saturation) at negligible complexity cost and with zero dependencies. The tradeoff is that the metric is not rigorously uniform, but in practice it eliminates the main failure mode (vivid colors absorbed into gray clusters).

**Why K-Means over median-cut or octree?**

Median-cut and octree are faster but designed for *palette quantization* (minimizing total reproduction error across all pixels). K-Means finds *globally representative clusters* — it naturally surfaces the most visually distinct colors as separate entries rather than splitting along the most-populated color region.

**Why are result types (`AnalysisResult`, `DominantColor`) structs?**

Value semantics mean every child view owns an independent copy of the data it received at render time. There is no risk of a background analysis run mutating data that a view is currently reading. The copying cost is negligible — `DominantColor` is ~64 bytes.

**Why `@StateObject` for `HueNavState` instead of `@State`?**

`NSEvent.addLocalMonitorForEvents` returns an opaque monitor token that must be stored and later passed to `NSEvent.removeMonitor`. Storing this token requires a reference type with stable identity across SwiftUI re-renders. `@StateObject` provides exactly this guarantee; `@State` with a struct would copy the token and the stored reference would become stale.

**Why store thumbnails at insert time in `HistoryStore`?**

The sidebar renders every frame that SwiftUI decides to redraw it (e.g., on hover, window resize). Scaling a multi-megapixel `NSImage` on each render would cause frame drops. Pre-computing a 56×56 thumbnail once at insert time makes sidebar drawing O(1) per frame regardless of the original image size.
