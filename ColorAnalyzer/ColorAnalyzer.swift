import SwiftUI
import AppKit

// MARK: - Data Models

struct DominantColor: Identifiable {
    let id = UUID()
    let color: NSColor
    let proportion: Double  // 0.0 - 1.0
    let hue: Double         // 0 - 360
    let saturation: Double  // 0 - 1
    let brightness: Double  // 0 - 1

    var swiftUIColor: Color { Color(nsColor: color) }
}

struct LuminanceHistogram {
    let bins: [Int]   // 256 bins
    var maxValue: Int { bins.max() ?? 1 }

    /// Linear normalization — bar height proportional to raw pixel count.
    /// A dominant background colour will produce one very tall bar that
    /// dwarfs everything else.
    func normalizedBins() -> [Double] {
        let maxVal = Double(maxValue)
        guard maxVal > 0 else { return Array(repeating: 0, count: bins.count) }
        return bins.map { Double($0) / maxVal }
    }

    /// Logarithmic normalization — compresses tall peaks so that minority
    /// tones are still visible. Formula: log(1+count) / log(1+maxCount).
    /// A white-background photo no longer produces a single overwhelming spike.
    func logNormalizedBins() -> [Double] {
        let logMax = log(1 + Double(maxValue))
        guard logMax > 0 else { return Array(repeating: 0, count: bins.count) }
        return bins.map { log(1 + Double($0)) / logMax }
    }
}

struct ColorPoint: Identifiable {
    let id = UUID()
    let hue: Double
    let saturation: Double
    let brightness: Double
    let proportion: Double
    let color: NSColor
}

struct AnalysisResult {
    let id = UUID()          // stable identity — used by HistoryStore to skip duplicate entries
    let image: NSImage
    let imageSize: CGSize
    let dominantColors: [DominantColor]
    let histogram: LuminanceHistogram
    let colorPoints: [ColorPoint]
    let processingTime: TimeInterval
}

// MARK: - Color Analysis Engine

class ColorAnalyzer: ObservableObject {
    @Published var result: AnalysisResult? = nil
    @Published var isAnalyzing = false
    @Published var errorMessage: String? = nil

    private let colorCount = 16
    private var lastImage: NSImage? = nil

    func analyze(image: NSImage) {
        lastImage = image
        isAnalyzing = true
        errorMessage = nil
        result = nil

        let k = colorCount

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let start = Date()

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async {
                    self?.errorMessage = "无法读取图片数据"
                    self?.isAnalyzing = false
                }
                return
            }

            // Sample pixels at reduced resolution for performance
            let sampleWidth = min(cgImage.width, 200)
            let sampleHeight = min(cgImage.height, 200)
            let pixels = self?.samplePixels(from: cgImage, width: sampleWidth, height: sampleHeight) ?? []

            let histogram = self?.buildHistogram(pixels: pixels) ?? LuminanceHistogram(bins: Array(repeating: 0, count: 256))
            let dominant = self?.kMeansClustering(pixels: pixels, k: k) ?? []
            let colorPoints = self?.buildColorPoints(pixels: pixels) ?? []
            let elapsed = Date().timeIntervalSince(start)
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

            DispatchQueue.main.async {
                self?.result = AnalysisResult(
                    image: image,
                    imageSize: imageSize,
                    dominantColors: dominant,
                    histogram: histogram,
                    colorPoints: colorPoints,
                    processingTime: elapsed
                )
                self?.isAnalyzing = false
            }
        }
    }

    func reanalyze() {
        guard let image = lastImage else { return }
        analyze(image: image)
    }

    /// Restores a previous result directly — no re-analysis, no new history entry.
    /// Called by the history sidebar so tapping a thumbnail is instant.
    func restore(result: AnalysisResult) {
        lastImage = result.image
        self.result = result
    }

    // MARK: - Pixel Sampling

    private func samplePixels(from cgImage: CGImage, width: Int, height: Int) -> [(h: Double, s: Double, b: Double, lum: Double)] {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return [] }

        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var result: [(h: Double, s: Double, b: Double, lum: Double)] = []
        result.reserveCapacity(width * height)

        for i in 0..<(width * height) {
            let r = Double(ptr[i * 4]) / 255.0
            let g = Double(ptr[i * 4 + 1]) / 255.0
            let b = Double(ptr[i * 4 + 2]) / 255.0
            let a = Double(ptr[i * 4 + 3]) / 255.0
            guard a > 0.1 else { continue }

            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            let color = NSColor(red: r, green: g, blue: b, alpha: 1)
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, al: CGFloat = 0
            color.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &al)
            result.append((h: Double(hue), s: Double(sat), b: Double(bri), lum: lum))
        }
        return result
    }

    // MARK: - Histogram

    private func buildHistogram(pixels: [(h: Double, s: Double, b: Double, lum: Double)]) -> LuminanceHistogram {
        var bins = Array(repeating: 0, count: 256)
        for px in pixels {
            let bin = min(255, Int(px.lum * 255))
            bins[bin] += 1
        }
        return LuminanceHistogram(bins: bins)
    }

    // MARK: - K-Means Clustering for Dominant Colors

    /// Extracts `k` dominant colors from the pixel sample using K-Means++ clustering.
    ///
    /// Design choices vs. standard K-Means:
    /// 1. **HSB space** — clustering is done in HSB rather than RGB so that the
    ///    distance metric can be made perceptually aware (see `hsbDist`).
    /// 2. **K-Means++ initialization** — the first centroid is chosen at random;
    ///    each subsequent centroid is sampled with probability ∝ distance² from
    ///    the nearest existing centroid. This spreads initial points across the
    ///    color space and guarantees an O(log k) approximation ratio vs. optimal.
    /// 3. **Adaptive saturation ranking** — after clustering, vivid colors are
    ///    promoted in the sort order when the overall image is desaturated,
    ///    preventing small accent colors from being buried below large gray clusters.
    private func kMeansClustering(pixels: [(h: Double, s: Double, b: Double, lum: Double)], k: Int) -> [DominantColor] {
        guard pixels.count >= k else { return [] }

        var centroids = initCentroidsHSB(pixels: pixels, k: k)
        var assignments = Array(repeating: 0, count: pixels.count)

        // Iterate until convergence or 20 rounds (whichever comes first)
        for _ in 0..<20 {
            var changed = false
            for i in 0..<pixels.count {
                let nearest = nearestCentroidHSB(pixel: pixels[i], centroids: centroids)
                if assignments[i] != nearest { changed = true }
                assignments[i] = nearest
            }
            if !changed { break }
            centroids = updateCentroidsHSB(pixels: pixels, assignments: assignments, k: k)
        }

        var counts = Array(repeating: 0, count: k)
        for a in assignments { counts[a] += 1 }
        let total = Double(pixels.count)

        var results: [DominantColor] = []
        for i in 0..<k {
            guard counts[i] > 0 else { continue }
            let c = centroids[i]
            let nsColor = NSColor(hue: c.h, saturation: c.s, brightness: c.b, alpha: 1)
            let proportion = Double(counts[i]) / total
            results.append(DominantColor(
                color: nsColor, proportion: proportion,
                hue: c.h * 360, saturation: c.s, brightness: c.b
            ))
        }

        // Adaptive saturation boost:
        // When the image mean saturation is below 0.35 (low-chroma photo — white walls,
        // overcast sky, desaturated film grade), compute a boost factor that scales
        // each cluster's ranking score by (1 + boost × saturation).
        // Effect: a vivid purple at 3% pixel coverage outranks a beige at 8% coverage
        // when boost ≈ 2–3, so the palette reflects the visually important colors.
        let meanSat = results.reduce(0.0) { $0 + $1.saturation * $1.proportion }
        let satBoost = max(0.0, (0.35 - meanSat) / 0.35) * 3.0

        return results
            .filter { $0.proportion > 0.01 }
            .filter { dc in
                // Drop near-white clusters that dominate the image (>51%); these are
                // almost always background and add no color information.
                !(dc.saturation < 0.12 && dc.brightness > 0.88 && dc.proportion > 0.51)
            }
            .sorted {
                let sa = $0.proportion * (1.0 + satBoost * $0.saturation)
                let sb = $1.proportion * (1.0 + satBoost * $1.saturation)
                return sa > sb
            }
    }

    // MARK: - Perceptual HSB Distance

    /// Custom distance metric for K-Means clustering in HSB space.
    ///
    /// **Why not RGB Euclidean distance?**
    /// RGB space is not perceptually uniform. A vivid purple and a neutral gray can be
    /// "closer" in RGB than two fully-saturated colors of different hues, causing K-Means
    /// to absorb small chromatic regions into large achromatic clusters.
    ///
    /// **The fix — saturation-modulated hue weight:**
    /// ```
    /// d = Δhue² × (1 + avgSat × 4) + ΔSat² + ΔBri² × 0.5
    /// ```
    /// When two pixels have high average saturation, the hue-difference term receives
    /// up to 5× weight. A vivid purple and a vivid red are therefore treated as much
    /// farther apart than two equally-hue-different grays, preserving their distinct
    /// clusters even when the purple region is small.
    ///
    /// - Note: Hue is in [0, 1]; the circular minimum `min(|Δh|, 1−|Δh|)` handles
    ///   the wraparound between 0° (red) and 360° (also red).
    private func hsbDist(h1: Double, s1: Double, b1: Double,
                         h2: Double, s2: Double, b2: Double) -> Double {
        let dh = min(abs(h1 - h2), 1.0 - abs(h1 - h2))  // circular distance, range [0, 0.5]
        let avgS = (s1 + s2) / 2
        let hueTerm = dh * dh * (1.0 + avgS * 4.0)       // up to 5× weight for saturated pairs
        let satTerm = pow(s1 - s2, 2)
        let briTerm = pow(b1 - b2, 2) * 0.5              // brightness weighted lower than hue
        return hueTerm + satTerm + briTerm
    }

    /// K-Means++ centroid initialization in HSB space.
    ///
    /// Each new centroid is sampled from the pixel set with probability proportional to
    /// its squared perceptual distance from the nearest existing centroid. This tends to
    /// spread centroids across visually distinct regions of the image, reducing the risk
    /// of multiple centroids collapsing into the same color cluster.
    private func initCentroidsHSB(pixels: [(h: Double, s: Double, b: Double, lum: Double)], k: Int) -> [(h: Double, s: Double, b: Double)] {
        var centroids: [(h: Double, s: Double, b: Double)] = []
        let first = pixels[Int.random(in: 0..<pixels.count)]
        centroids.append((first.h, first.s, first.b))

        while centroids.count < k {
            // For each pixel, find its squared distance to the nearest centroid
            let distances: [Double] = pixels.map { px in
                centroids.map { c in
                    hsbDist(h1: px.h, s1: px.s, b1: px.b, h2: c.h, s2: c.s, b2: c.b)
                }.min() ?? 0
            }
            // Sample the next centroid using distances as a probability distribution
            let total = distances.reduce(0, +)
            guard total > 0 else { break }
            var rand = Double.random(in: 0..<total)
            for (i, d) in distances.enumerated() {
                rand -= d
                if rand <= 0 { centroids.append((pixels[i].h, pixels[i].s, pixels[i].b)); break }
            }
        }
        return centroids
    }

    private func nearestCentroidHSB(pixel: (h: Double, s: Double, b: Double, lum: Double),
                                     centroids: [(h: Double, s: Double, b: Double)]) -> Int {
        var minDist = Double.infinity
        var nearest = 0
        for (i, c) in centroids.enumerated() {
            let d = hsbDist(h1: pixel.h, s1: pixel.s, b1: pixel.b, h2: c.h, s2: c.s, b2: c.b)
            if d < minDist { minDist = d; nearest = i }
        }
        return nearest
    }

    /// Updates cluster centroids after reassignment.
    ///
    /// **Circular mean for hue:**
    /// Hue is a circular variable — arithmetic averaging fails at the 0°/360° boundary.
    /// Example: averaging 10° and 350° arithmetically gives 180° (cyan), not 0° (red).
    ///
    /// The correct approach maps each hue to a unit-circle vector (cos θ, sin θ),
    /// averages the vectors, then converts back via atan2:
    /// ```
    /// meanHue = atan2(Σ sin(hᵢ), Σ cos(hᵢ))
    /// ```
    /// For 10° and 350°, the sin components cancel (±0.174) and the cos components
    /// reinforce (+0.985 each), giving atan2(0, 1.97) = 0°. ✓
    ///
    /// Saturation and brightness use ordinary arithmetic means.
    private func updateCentroidsHSB(pixels: [(h: Double, s: Double, b: Double, lum: Double)],
                                     assignments: [Int], k: Int) -> [(h: Double, s: Double, b: Double)] {
        var sinSum = Array(repeating: 0.0, count: k)
        var cosSum = Array(repeating: 0.0, count: k)
        var sSum   = Array(repeating: 0.0, count: k)
        var bSum   = Array(repeating: 0.0, count: k)
        var counts = Array(repeating: 0,   count: k)

        for (i, a) in assignments.enumerated() {
            let px = pixels[i]
            let angle = px.h * 2 * .pi   // hue [0,1] → radians [0, 2π]
            sinSum[a] += sin(angle)
            cosSum[a] += cos(angle)
            sSum[a]   += px.s
            bSum[a]   += px.b
            counts[a] += 1
        }
        return (0..<k).map { i in
            let n = Double(max(1, counts[i]))
            var hue = atan2(sinSum[i] / n, cosSum[i] / n) / (2 * .pi)
            if hue < 0 { hue += 1.0 }   // atan2 returns [-π, π]; shift to [0, 1]
            return (h: hue, s: sSum[i] / n, b: bSum[i] / n)
        }
    }

    // MARK: - Color Points for Hue Wheel

    private func buildColorPoints(pixels: [(h: Double, s: Double, b: Double, lum: Double)]) -> [ColorPoint] {
        // Bin pixels into hue/sat cells and aggregate
        var grid: [String: (count: Int, h: Double, s: Double, b: Double)] = [:]
        for px in pixels {
            let hBin = Int(px.h * 36) // 36 hue bins
            let sBin = Int(px.s * 10) // 10 sat bins
            let key = "\(hBin)_\(sBin)"
            if var existing = grid[key] {
                existing.count += 1
                existing.b = (existing.b + px.b) / 2
                grid[key] = existing
            } else {
                grid[key] = (count: 1, h: px.h, s: px.s, b: px.b)
            }
        }

        let total = Double(pixels.count)
        return grid.map { (_, v) in
            let c = NSColor(hue: v.h, saturation: v.s, brightness: v.b, alpha: 1)
            return ColorPoint(hue: v.h * 360, saturation: v.s, brightness: v.b,
                              proportion: Double(v.count) / total, color: c)
        }.filter { $0.proportion > 0.001 }.sorted { $0.proportion > $1.proportion }.prefix(200).map { $0 }
    }
}
