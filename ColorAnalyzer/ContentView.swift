import SwiftUI
import AppKit

// MARK: - History Store

/// Ring-buffer of the last 10 analysis results.
/// Stores the full AnalysisResult so history items can be restored instantly
/// without re-running the clustering pipeline.
final class HistoryStore: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let result: AnalysisResult   // full result — enables instant restore
        let thumbnail: NSImage       // pre-scaled 56×56 for cheap sidebar drawing
        let date: Date
    }

    @Published var entries: [Entry] = []
    private static let maxCount = 10

    /// Adds or promotes a result.
    /// If the result already exists anywhere in history, it is moved to the
    /// front (no new entry created). This ensures that restoring a history
    /// item never inflates the list — the total count stays the same.
    func add(_ result: AnalysisResult) {
        if let idx = entries.firstIndex(where: { $0.result.id == result.id }) {
            let existing = entries.remove(at: idx)
            entries.insert(existing, at: 0)
            return
        }
        let thumb = result.image.scaledToFit(NSSize(width: 56, height: 56))
        entries.insert(Entry(result: result, thumbnail: thumb, date: Date()), at: 0)
        if entries.count > Self.maxCount { entries.removeLast() }
    }
}

private extension NSImage {
    /// Returns a copy scaled to fit within `target` preserving aspect ratio.
    func scaledToFit(_ target: NSSize) -> NSImage {
        let s = size
        guard s.width > 0, s.height > 0 else { return self }
        let scale = min(target.width / s.width, target.height / s.height)
        let newSize = NSSize(width: s.width * scale, height: s.height * scale)
        let out = NSImage(size: newSize)
        out.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: s),
             operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var analyzer = ColorAnalyzer()
    @StateObject private var history  = HistoryStore()
    @State private var isDragging = false

    var body: some View {
        HSplitView {
            // Far-left thumbnail history strip — restore result directly, no re-analysis
            HistorySidebar(store: history) { entry in
                analyzer.restore(result: entry.result)
            }
            .frame(minWidth: 72, maxWidth: 72)

            LeftPanel(analyzer: analyzer, isDragging: $isDragging)
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)

            RightPanel(analyzer: analyzer)
                .frame(minWidth: 600)
        }
        .background(Color(NSColor.windowBackgroundColor))
        // Record every completed analysis in the history sidebar.
        // HistoryStore.add() skips duplicates via result.id, so restoring
        // from history never creates a second entry.
        .onReceive(analyzer.$result) { result in
            if let result = result { history.add(result) }
        }
        // Cmd+V: paste an image directly from the clipboard
        .background(
            Button("") { pasteImage() }
                .keyboardShortcut("v", modifiers: .command)
                .hidden()
        )
    }

    private func pasteImage() {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else { return }
        analyzer.analyze(image: image)
    }
}

// MARK: - History Sidebar

struct HistorySidebar: View {
    @ObservedObject var store: HistoryStore
    let onSelect: (HistoryStore.Entry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("最近")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if store.entries.isEmpty {
                Spacer()
                Image(systemName: "clock")
                    .font(.system(size: 20, weight: .ultraLight))
                    .foregroundColor(.secondary.opacity(0.35))
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(store.entries) { entry in
                            Button { onSelect(entry) } label: {
                                Image(nsImage: entry.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipped()
                                    .cornerRadius(7)
                                    .overlay(RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help(shortTime(entry.date))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - Left Panel

struct LeftPanel: View {
    @ObservedObject var analyzer: ColorAnalyzer
    @Binding var isDragging: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("色彩分析仪")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if analyzer.result == nil {
                // No image: drop zone fills the full panel so it aligns with the right-side empty state
                ImageDropZone(analyzer: analyzer, isDragging: $isDragging, isCompact: false)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Compact "replace image" strip
                        ImageDropZone(analyzer: analyzer, isDragging: $isDragging, isCompact: true)
                            .padding(.top, 12)

                        if let result = analyzer.result {
                            ImagePreviewCard(result: result)
                        }
                        if let result = analyzer.result {
                            HistogramCard(result: result)
                        }
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: - Image Drop Zone

struct ImageDropZone: View {
    @ObservedObject var analyzer: ColorAnalyzer
    @Binding var isDragging: Bool
    var isCompact: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isCompact ? 8 : 14)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color(NSColor.separatorColor),
                    style: StrokeStyle(lineWidth: isDragging ? 2 : 1.5, dash: isDragging ? [] : [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: isCompact ? 8 : 14)
                        .fill(isDragging ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                )

            if analyzer.isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(isCompact ? 0.7 : 0.85)
                    Text("分析中…")
                        .font(.system(size: isCompact ? 12 : 13))
                        .foregroundColor(.secondary)
                }
            } else if isCompact {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(isDragging ? .accentColor : .secondary)
                    Text(isDragging ? "松开以替换图片" : "更换图片")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDragging ? .accentColor : .secondary)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .ultraLight))
                        .foregroundColor(isDragging ? .accentColor : .secondary)
                    Text("拖放图片到这里")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isDragging ? .accentColor : .primary)
                    Text("或点击选择文件")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(height: isCompact ? 42 : nil)
        .frame(maxWidth: .infinity, maxHeight: isCompact ? nil : .infinity)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .onTapGesture { openFilePicker() }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let image = NSImage(contentsOf: url) {
            analyzer.analyze(image: image)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   let image = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { self.analyzer.analyze(image: image) }
                }
            }
            return true
        }
        return false
    }
}

// MARK: - Image Preview Card

struct ImagePreviewCard: View {
    let result: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(nsImage: result.image)
                .resizable()
                .scaledToFit()
                .cornerRadius(8)
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)

            HStack {
                Label("\(Int(result.imageSize.width)) × \(Int(result.imageSize.height)) px",
                      systemImage: "aspectratio")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Histogram Card

struct HistogramCard: View {
    let result: AnalysisResult

    private var histogram: LuminanceHistogram { result.histogram }

    private var zones: (dark: Double, mid: Double, bright: Double) {
        let total = max(1, histogram.bins.reduce(0, +))
        let dark   = histogram.bins[0..<86].reduce(0, +)
        let mid    = histogram.bins[86..<171].reduce(0, +)
        let bright = histogram.bins[171..<256].reduce(0, +)
        return (Double(dark) / Double(total) * 100,
                Double(mid)  / Double(total) * 100,
                Double(bright) / Double(total) * 100)
    }

    private func meanV(from: Int, to: Int) -> Double {
        var sum = 0.0; var count = 0
        for i in from..<to {
            sum += Double(i) * Double(histogram.bins[i])
            count += histogram.bins[i]
        }
        guard count > 0 else { return Double(from + to) / 2.0 / 255.0 * 100 }
        return sum / Double(count) / 255.0 * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── Header: title + compact image stats ──────────────────────────
            HStack(alignment: .firstTextBaseline) {
                Text("明暗分布")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(Int(result.imageSize.width))×\(Int(result.imageSize.height))")
                    Text("·")
                    Text("\(result.dominantColors.count) 色")
                    Text("·")
                    Text(String(format: "覆盖 %.0f%%",
                                result.dominantColors.reduce(0) { $0 + $1.proportion } * 100))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }

            HistogramView(histogram: histogram)
                .frame(height: 58)

            let z = zones
            HStack(spacing: 4) {
                ZoneStat(label: "暗区",  range: "0–33%",   percent: z.dark,
                         tone: 0.15, meanV: meanV(from: 0,   to: 86))
                ZoneStat(label: "中调",  range: "34–67%",  percent: z.mid,
                         tone: 0.50, meanV: meanV(from: 86,  to: 171))
                ZoneStat(label: "亮区",  range: "67–100%", percent: z.bright,
                         tone: 0.90, meanV: meanV(from: 171, to: 256))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct ZoneStat: View {
    let label: String
    let range: String
    let percent: Double
    let tone: Double      // 0=black … 1=white, for tint
    let meanV: Double     // weighted mean brightness 0-100, for painting reference

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(white: tone))
                    .overlay(Circle().stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                    .frame(width: 9, height: 9)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            VStack(spacing: 1) {
                Text(range)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("明度区间")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            Divider().padding(.horizontal, 6)

            // Pixel proportion
            VStack(spacing: 1) {
                Text(String(format: "%.1f%%", percent))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("像素占比")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            Divider().padding(.horizontal, 6)

            // Mean V for painting
            VStack(spacing: 1) {
                Text(String(format: "V %.0f%%", meanV))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("均值明度")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(white: tone).opacity(tone > 0.5 ? 0.07 : 0.12))
        .cornerRadius(7)
    }
}

struct HistogramView: View {
    let histogram: LuminanceHistogram
    @State private var hoverX: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let bins = histogram.logNormalizedBins()   // log scale — prevents single dominant spike
            let barW = geo.size.width / CGFloat(bins.count)

            ZStack(alignment: .bottomLeading) {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.15), Color.white.opacity(0.3)]),
                    startPoint: .leading, endPoint: .trailing
                )
                .cornerRadius(6)

                // Bars
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<bins.count, id: \.self) { i in
                        let t = Double(i) / Double(bins.count)
                        Rectangle()
                            .fill(Color(hue: 0, saturation: 0, brightness: t).opacity(0.75))
                            .frame(width: barW, height: CGFloat(bins[i]) * geo.size.height)
                    }
                }

                // Zone dividers at 33% and 67%
                Path { path in
                    let x1 = geo.size.width * (86.0 / 256.0)
                    let x2 = geo.size.width * (171.0 / 256.0)
                    path.move(to: CGPoint(x: x1, y: 0))
                    path.addLine(to: CGPoint(x: x1, y: geo.size.height))
                    path.move(to: CGPoint(x: x2, y: 0))
                    path.addLine(to: CGPoint(x: x2, y: geo.size.height))
                }
                .stroke(Color.white.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Hover cursor line
                if let hx = hoverX {
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1, height: geo.size.height)
                        .position(x: hx, y: geo.size.height / 2)

                    // V% label above cursor
                    let vPct = hx / geo.size.width * 100
                    Text(String(format: "V %.0f%%", vPct))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .position(x: max(24, min(geo.size.width - 24, hx)),
                                  y: 10)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoverX = max(0, min(geo.size.width, loc.x))
                case .ended:
                    hoverX = nil
                }
            }
        }
    }
}
