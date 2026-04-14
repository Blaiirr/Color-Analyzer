# Color Analyzer 色彩分析仪

> A native macOS color analysis tool — drag in any image to instantly extract dominant colors, explore the hue wheel, and study luminance statistics.  
> macOS 原生色彩分析工具，拖入图片即刻获得主色调、交互色环与明度直方图分析。

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

## Screenshots

| 全色显示模式 | 主色模式 |
|:-----------:|:-------:|
| ![全色显示](Screenshots/Screenshot%202026-04-13%20at%2021.08.11.png) | ![主色模式](Screenshots/Screenshot%202026-04-13%20at%2021.08.21.png) |

| 色相分布 · 饱和度明度矩阵 | 低饱和图片 · 自适应排序 |
|:------------------------:|:----------------------:|
| ![色相分布](Screenshots/Screenshot%202026-04-13%20at%2021.08.37.png) | ![低饱和](Screenshots/Screenshot%202026-04-13%20at%2021.09.07.png) |

---

## Features

| Feature | Detail |
|---------|--------|
| **16-color K-Means++ extraction** | Clusters in perceptual HSB space — vivid accent colors surface even when they occupy only 2–3% of the image |
| **Interactive hue wheel** | Two display modes: **全色显示** renders all sampled color points on the wheel; **主色模式** shows only the dominant color markers |
| **S×B square** | Inner square of the wheel filters to the selected hue range — scatter dots in 全色显示, ring markers in 主色模式 |
| **Luminance histogram** | Log-scale bar chart with hover tooltip (V%); divided into dark / mid / bright zones with weighted mean brightness per zone |
| **Stats inline** | Resolution, dominant color count, and coverage percentage live in the histogram header — no separate stats row |
| **Clipboard copy** | Click any color chip to copy HEX; right-click for RGB or HSB formats; checkmark confirms the copy |
| **⌘V paste** | Paste an image directly from the clipboard to analyze it immediately |
| **Recent history** | Left sidebar keeps the last 10 analyzed images; clicking a thumbnail restores the result instantly — no re-analysis, no duplicate entry |
| **Keyboard navigation** | `←` / `→` cycles through dominant hues on the color wheel |
| **Drag & drop / file picker** | Drop an image anywhere on the left panel, or click to open a file picker |

---

## Download

[**ColorAnalyzer-1.0.dmg**](../../releases) — macOS 13 Ventura or later, Apple Silicon & Intel

> **First launch:** The app is unsigned. Right-click → Open to bypass Gatekeeper, or run:
> ```bash
> xattr -d com.apple.quarantine ColorAnalyzer.app
> ```

---

## Build from Source

```bash
git clone https://github.com/<you>/ColorAnalyzer.git
open ColorAnalyzer/ColorAnalyzer.xcodeproj
```

1. In *Signing & Capabilities*, select your team (a free Apple ID works for local builds)
2. Press `⌘R` to run
3. To produce a distributable `.app`: `Product → Archive → Distribute App → Copy App`

**Zero external dependencies** — pure Swift + Apple frameworks only.

---

## Algorithm Highlights

This section explains the non-trivial engineering choices. The goal throughout is to make the output match **human visual perception**, not just raw pixel statistics.

### 1 · K-Means++ Initialization

Standard K-Means picks random starting centroids, often placing several inside the same large color cluster. K-Means++ selects each subsequent centroid with probability proportional to its **squared distance** from the nearest existing centroid:

```
P(pixel i chosen as next centroid) ∝ min_j d(i, j)²
```

This spreads initial centroids across visually distinct regions and provides a theoretical bound: expected error is within **O(log k)** of the global optimum, versus no guarantee for random initialization.

### 2 · Perceptual HSB Distance

RGB Euclidean distance is perceptually non-uniform. A vivid purple and a neutral gray can have a *smaller* RGB distance than two fully-saturated colors of different hues — causing K-Means to silently absorb small chromatic regions into large achromatic clusters, making vivid accent colors vanish from the output.

The custom distance metric amplifies hue differences by average saturation:

```
d(a, b) = Δhue² × (1 + avgSat × 4)  +  ΔSat²  +  ΔBri² × 0.5
```

When two pixels are both highly saturated, the hue term receives **up to 5× weight**. A vivid purple is therefore very "far" from a vivid red in this metric, guaranteeing it forms its own cluster even when it represents only 2–3% of the image.

*This replicates the perceptual uniformity of CIE Lab without the RGB→XYZ→Lab pipeline and with zero external dependencies.*

### 3 · Circular Mean for Hue

Hue is a **circular variable** — 0° and 360° represent the same red. Arithmetic averaging fails at the boundary: the mean of 10° and 350° is 180° (cyan), not 0° (red).

The correct approach uses **unit-circle vector addition**:

```
sinMean = Σ sin(hᵢ · 2π)  /  n
cosMean = Σ cos(hᵢ · 2π)  /  n
meanHue = atan2(sinMean, cosMean)
```

For 10° and 350°: sin components cancel (0.174 − 0.174 = 0), cos components reinforce (0.985 + 0.985 = 1.97), giving `atan2(0, 1.97) = 0°`. ✓

Without this, K-Means converges to wrong centroids for any cluster that straddles 0°/360° — and the bug is invisible because the algorithm still "converges."

### 4 · Adaptive Saturation Ranking

After clustering, colors are sorted by a **weighted score** rather than raw pixel proportion:

```
meanSat  = Σ (proportion_i × saturation_i)        // image-level average
boost    = max(0, (0.35 − meanSat) / 0.35) × 3    // 0 when image is chromatic
score_i  = proportion_i × (1 + boost × saturation_i)
```

When the image is already chromatic (meanSat ≥ 0.35), boost = 0 and ranking is by proportion as normal. When the image is mostly gray or beige, vivid clusters receive up to a **4× ranking uplift**, ensuring a small splash of teal or purple appears near the top of the palette rather than buried behind near-identical grays.

### 5 · Logarithmic Histogram Normalization

A raw linear histogram often has one overwhelming spike — a white background or uniform sky floods one bin and compresses all other tones into invisibility.

```
barHeight = log(1 + count) / log(1 + maxCount)
```

The logarithm compresses tall peaks and stretches short ones. A dominant-white image still shows its spike, but shadow and midtone detail remain readable at the same time.

### 6 · Async Analysis + Reactive UI

The entire clustering pipeline runs on `DispatchQueue.global(qos: .userInitiated)` to keep the UI frame rate smooth during the ~100 ms analysis step. Results are published on `DispatchQueue.main` via `@Published` properties on a single `ObservableObject`. SwiftUI's diffing engine handles all downstream re-renders — no manual notification or synchronization code required.

The history sidebar uses `.onReceive(analyzer.$result)` rather than `onChange(of:)` because `NSImage` does not conform to `Equatable`, and `onChange` requires `Equatable` values. `onReceive` subscribes directly to the Combine publisher without equality comparison.

---

## Complexity

| Step | Complexity | Typical time |
|------|-----------|-------------|
| Pixel sampling | O(W × H) | < 5 ms |
| Histogram build | O(n) | < 1 ms |
| K-Means++ init | O(n × k) | < 10 ms |
| K-Means iterations | O(n × k × iter) | ~80 ms |
| Color point aggregation | O(n) | < 2 ms |

*n ≤ 40 000 (200 × 200 sample grid), k = 16, iter ≤ 20*

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI framework | SwiftUI (macOS 13+) |
| Drawing | SwiftUI `Canvas`, `GeometryReader`, `Path` |
| Reactive state | `@Published` / `ObservableObject` / Combine |
| Concurrency | `DispatchQueue.global` + `DispatchQueue.main` |
| Color science | Custom perceptual HSB distance, circular statistics |
| Algorithms | K-Means++, vector mean for circular variables, log normalization |
| External deps | **None** |

---

## Project Structure

```
ColorAnalyzer/
├── ColorAnalyzer.swift    Data models + analysis engine (K-Means++, histogram, color points)
├── ContentView.swift      3-pane shell, HistoryStore, drop zone, paste handler, histogram card
├── RightPanel.swift       All result views — color strip, interactive hue wheel, hue scatter
└── PDFExporter.swift      Export stub (reserved for future use)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full data-flow diagram and component design decisions.

---

## License

MIT
