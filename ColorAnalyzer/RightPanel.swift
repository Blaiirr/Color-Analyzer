import SwiftUI
import AppKit

// MARK: - Right Panel

struct RightPanel: View {
    @ObservedObject var analyzer: ColorAnalyzer

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("分析结果")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if analyzer.result == nil && !analyzer.isAnalyzing {
                emptyState
            } else if let result = analyzer.result {
                ScrollView {
                    VStack(spacing: 20) {
                        // Color strip — compact; the wheel is the main feature
                        ColorStripCard(dominantColors: result.dominantColors)

                        // Interactive color wheel — main feature, sits right below strip
                        ColorWheelPickerCard(dominantColors: result.dominantColors,
                                             colorPoints: result.colorPoints)

                        // Hue scatter + S×V overview — secondary analysis below
                        HueWheelCard(colorPoints: result.colorPoints, dominantColors: result.dominantColors)
                    }
                    .padding(20)
                }
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.secondary.opacity(0.5))
            Text("导入图片后查看色彩分析")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Overview Stats

struct OverviewStatsRow: View {
    let result: AnalysisResult

    var body: some View {
        HStack(spacing: 12) {
            StatCard(title: "分辨率",
                     value: "\(Int(result.imageSize.width))×\(Int(result.imageSize.height))",
                     unit: "px")
            StatCard(title: "主色数",
                     value: "\(result.dominantColors.count)",
                     unit: "种")
            StatCard(title: "色彩覆盖",
                     value: String(format: "%.0f", result.dominantColors.reduce(0) { $0 + $1.proportion } * 100),
                     unit: "%")
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Color Strip

struct ColorStripCard: View {
    let dominantColors: [DominantColor]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("主色带")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(dominantColors) { dc in
                        colorBlock(dc, totalWidth: geo.size.width)
                    }
                }
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
            }
            .frame(height: 28)

            // Color chips row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dominantColors) { dc in
                        ColorChip(dominantColor: dc)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func colorBlock(_ dc: DominantColor, totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(dc.swiftUIColor)
            .frame(width: max(1, totalWidth * dc.proportion))
    }
}

struct ColorChip: View {
    let dominantColor: DominantColor
    @State private var isHovered = false
    @State private var copied = false

    private var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        dominantColor.color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
    private var rgbString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        dominantColor.color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r*255)), \(Int(g*255)), \(Int(b*255)))"
    }
    private var hsbString: String {
        "hsb(\(Int(dominantColor.hue))°, \(Int(dominantColor.saturation*100))%, \(Int(dominantColor.brightness*100))%)"
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(dominantColor.swiftUIColor)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.spring(response: 0.2), value: isHovered)
                if copied {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            Text(copied ? "已复制" : hexString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(copied ? .accentColor : .secondary)
                .animation(.easeInOut(duration: 0.15), value: copied)
            Text(String(format: "%.0f%%", dominantColor.proportion * 100))
                .font(.system(size: 10, weight: .medium))
        }
        .onHover { isHovered = $0 }
        .onTapGesture { paste(hexString) }
        .contextMenu {
            Button("复制 HEX   \(hexString)") { paste(hexString) }
            Button("复制 RGB   \(rgbString)") { paste(rgbString) }
            Button("复制 HSB   \(hsbString)") { paste(hsbString) }
        }
        .help("点击复制 HEX · 右键更多格式")
    }

    private func paste(_ str: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

// MARK: - Hue Wheel

struct HueWheelCard: View {
    let colorPoints: [ColorPoint]
    let dominantColors: [DominantColor]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("色相分布")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("饱和度 · 明度总览")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                // Scatter hue wheel
                HueWheelView(colorPoints: colorPoints, dominantColors: dominantColors)
                    .frame(width: 300, height: 300)

                // Static SB square — strictly 1:1 aspect ratio
                AllColorsSBView(dominantColors: dominantColors)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct HueWheelView: View {
    let colorPoints: [ColorPoint]
    let dominantColors: [DominantColor]
    @State private var hoveredPoint: ColorPoint? = nil

    // Layout params: no ring, scatter fills the full circle
    private func params(for size: CGSize) -> (center: CGPoint, radius: CGFloat, maxR: CGFloat) {
        let r = min(size.width, size.height) / 2 - 20   // leave edge for labels
        return (CGPoint(x: size.width / 2, y: size.height / 2), r, r - 4)
    }

    private func dotSize(_ pt: ColorPoint) -> CGFloat {
        CGFloat(max(7, min(30, sqrt(pt.proportion) * 200)))
    }

    private func dotPos(_ pt: ColorPoint, center: CGPoint, maxR: CGFloat) -> CGPoint {
        let angle = (pt.hue - 90) * .pi / 180
        let r = pt.saturation * maxR
        return CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
    }

    private func findHovered(at loc: CGPoint, size: CGSize) -> ColorPoint? {
        let (center, _, maxR) = params(for: size)
        return colorPoints
            .sorted { $0.proportion > $1.proportion }   // larger dots win on overlap
            .first { pt in
                let p = dotPos(pt, center: center, maxR: maxR)
                let dx = loc.x - p.x, dy = loc.y - p.y
                return sqrt(dx*dx + dy*dy) < dotSize(pt) / 2 + 5
            }
    }

    var body: some View {
        GeometryReader { geo in
            let (center, radius, maxR) = params(for: geo.size)

            ZStack {
                // Background circle
                Circle()
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)

                // Grid spokes
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) * .pi / 6
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: CGPoint(x: center.x + cos(angle) * radius,
                                                 y: center.y + sin(angle) * radius))
                    }
                    .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 0.5)
                }

                // Concentric rings
                ForEach([0.33, 0.66, 1.0], id: \.self) { t in
                    Circle()
                        .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5)
                        .frame(width: maxR * 2 * t, height: maxR * 2 * t)
                        .position(center)
                }

                // Scatter dots
                ForEach(colorPoints) { pt in
                    let pos = dotPos(pt, center: center, maxR: maxR)
                    let sz  = dotSize(pt)
                    Circle()
                        .fill(Color(nsColor: pt.color))
                        .frame(width: sz, height: sz)
                        .opacity(0.75 + pt.brightness * 0.25)
                        .shadow(color: Color(nsColor: pt.color).opacity(0.5), radius: 3)
                        .position(pos)
                }

                // Dominant color markers (3-ring style, in scatter area)
                ForEach(dominantColors.prefix(8)) { dc in
                    let pos = dotPos(
                        ColorPoint(hue: dc.hue, saturation: dc.saturation,
                                   brightness: dc.brightness, proportion: dc.proportion,
                                   color: dc.color),
                        center: center, maxR: maxR)
                    ZStack {
                        Circle().fill(Color.black.opacity(0.25)).frame(width: 16, height: 16)
                        Circle().fill(Color.white).frame(width: 13, height: 13)
                        Circle().fill(Color(nsColor: dc.color)).frame(width: 10, height: 10)
                    }
                    .position(pos)
                }

                // Hovered dot highlight
                if let hp = hoveredPoint {
                    let pos = dotPos(hp, center: center, maxR: maxR)
                    let sz  = dotSize(hp)
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: sz + 6, height: sz + 6)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .position(pos)
                }

                // Hue labels just outside the scatter circle
                hueLabels(center: center, radius: radius)

                // Hover detection overlay (must be on top of all static content)
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            hoveredPoint = findHovered(at: loc, size: geo.size)
                        case .ended:
                            hoveredPoint = nil
                        }
                    }

                // Tooltip — appears above everything
                if let hp = hoveredPoint {
                    let pos = dotPos(hp, center: center, maxR: maxR)
                    HuePointTooltip(point: hp)
                        .position(tooltipAnchor(dot: pos, viewSize: geo.size))
                        .zIndex(100)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func tooltipAnchor(dot: CGPoint, viewSize: CGSize) -> CGPoint {
        let w: CGFloat = 170, h: CGFloat = 46
        var tx = dot.x + 14
        var ty = dot.y - h / 2
        if tx + w > viewSize.width  { tx = dot.x - w - 14 }
        if ty < 2                   { ty = 2 }
        if ty + h > viewSize.height { ty = viewSize.height - h }
        return CGPoint(x: tx + w / 2, y: ty + h / 2)
    }

    @ViewBuilder
    private func hueLabels(center: CGPoint, radius: CGFloat) -> some View {
        let labels = [("红", 0.0), ("黄", 60.0), ("绿", 120.0), ("青", 180.0), ("蓝", 240.0), ("紫", 300.0)]
        ForEach(labels, id: \.0) { label, hue in
            let angle = (hue - 90) * .pi / 180
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .position(x: center.x + cos(angle) * (radius + 12),
                          y: center.y + sin(angle) * (radius + 12))
        }
    }
}

// MARK: - Hue scatter hover tooltip

struct HuePointTooltip: View {
    let point: ColorPoint

    private var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        point.color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: point.color))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(hex)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text("H:\(Int(point.hue))° S:\(Int(point.saturation * 100))% V:\(Int(point.brightness * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 6)
        .fixedSize()
    }
}

// MARK: - All-colors S·V overview (static, no hue filter)

struct AllColorsSBView: View {
    let dominantColors: [DominantColor]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Neutral background: white (top-left) → mid-gray (top-right) → black (bottom)
                ZStack {
                    LinearGradient(colors: [.white, Color(white: 0.55)],
                                   startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black],
                                   startPoint: .top, endPoint: .bottom)
                }
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5))

                // Axis labels
                Text("S →")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .position(x: geo.size.width - 18, y: geo.size.height - 11)
                Text("V ↑")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .position(x: 13, y: 11)

                // All dominant colors at their (S, V) position
                ForEach(dominantColors) { dc in
                    let x = max(10, min(geo.size.width  - 10, dc.saturation * geo.size.width))
                    let y = max(10, min(geo.size.height - 10, (1.0 - dc.brightness) * geo.size.height))
                    ZStack {
                        Circle().fill(Color.black.opacity(0.35)).frame(width: 19, height: 19)
                        Circle().fill(Color.white).frame(width: 16, height: 16)
                        Circle().fill(Color(nsColor: dc.color)).frame(width: 12, height: 12)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - Hue Ring Shape

struct HueRingShape: Shape {
    let radius: CGFloat
    let ringWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Outer circle
        path.addEllipse(in: CGRect(
            x: -radius, y: -radius,
            width: radius * 2, height: radius * 2
        ))
        // Inner circle (subtracted via even-odd fill rule)
        let inner = radius - ringWidth
        path.addEllipse(in: CGRect(
            x: -inner, y: -inner,
            width: inner * 2, height: inner * 2
        ))
        return path
    }
}

// Custom drawing for hue ring using canvas
extension View {
    func hueRingCanvas(radius: CGFloat) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let segments = 360
            for i in 0..<segments {
                let startAngle = Angle(degrees: Double(i) - 90)
                let endAngle = Angle(degrees: Double(i + 1) - 90)
                let path = Path { p in
                    p.move(to: center)
                    p.addArc(center: center, radius: radius,
                             startAngle: startAngle, endAngle: endAngle, clockwise: false)
                }
                let hue = Double(i) / 360.0
                context.fill(path, with: .color(Color(hue: hue, saturation: 1, brightness: 1)))
            }
        }
    }
}

// Better hue ring using Canvas
struct HueRingCanvas: View {
    let radius: CGFloat
    let ringWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let segments = 360
            for i in 0..<segments {
                let startRad = (Double(i) - 90) * .pi / 180
                let endRad = (Double(i + 1) - 90) * .pi / 180
                let path = Path { p in
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: radius,
                             startAngle: .radians(startRad), endAngle: .radians(endRad), clockwise: false)
                    p.addArc(center: CGPoint(x: cx, y: cy), radius: radius - ringWidth,
                             startAngle: .radians(endRad), endAngle: .radians(startRad), clockwise: true)
                    p.closeSubpath()
                }
                let hue = Double(i) / 360.0
                context.fill(path, with: .color(Color(hue: hue, saturation: 1, brightness: 1)))
            }
        }
    }
}

// Replace HueRingShape usage in HueWheelView with HueRingCanvas
// (Done above with Canvas approach)

// MARK: - Keyboard-navigable hue state (class for reference capture in NSEvent monitor)

private final class HueNavState: ObservableObject {
    @Published var hue: Double = 0
    private var monitor: Any? = nil

    func install(sortedColors: [DominantColor]) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 123: // ←
                DispatchQueue.main.async { self.step(by: -1, in: sortedColors) }
                return nil
            case 124: // →
                DispatchQueue.main.async { self.step(by: +1, in: sortedColors) }
                return nil
            default:
                return event
            }
        }
    }

    func remove() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func step(by delta: Int, in sorted: [DominantColor]) {
        guard !sorted.isEmpty else { return }
        let idx = sorted.enumerated()
            .min(by: { hueDiff($0.element.hue, hue) < hueDiff($1.element.hue, hue) })?
            .offset ?? 0
        let next = (idx + delta + sorted.count) % sorted.count
        withAnimation(.spring(response: 0.3)) { hue = sorted[next].hue }
    }

    private func hueDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}

// MARK: - Interactive Color Wheel Picker Card

struct ColorWheelPickerCard: View {
    let dominantColors: [DominantColor]
    let colorPoints: [ColorPoint]
    @StateObject private var nav = HueNavState()
    /// false = 全色显示 (scatter dots in SB square)
    /// true  = 主色模式 (dominant color markers only in SB square)
    @State private var dominantOnly = false

    private var selectedHue: Double { nav.hue }
    private var selectedHueBinding: Binding<Double> { Binding(get: { nav.hue }, set: { nav.hue = $0 }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 10) {
                Text("色环取色参考")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Mode switcher: 全色显示 ↔ 主色模式
                Picker("", selection: $dominantOnly) {
                    Text("全色显示").tag(false)
                    Text("主色模式").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)

                // Current hue indicator
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hue: selectedHue / 360, saturation: 1, brightness: 1))
                        .frame(width: 13, height: 13)
                        .overlay(RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                    Text("H: \(Int(selectedHue))°  拖动 / ←→")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // ── Large wheel — fills card width, 1:1 square ─────────────────
            InteractiveColorWheelView(
                dominantColors: dominantColors,
                colorPoints: colorPoints,
                dominantOnly: dominantOnly,
                selectedHue: selectedHueBinding
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)

            // ── Horizontal color legend ────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(dominantColors) { dc in
                        WheelColorChip(dc: dc,
                                       near: hueDiff(dc.hue, selectedHue) < 40,
                                       hex: hexString(dc))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            if let first = dominantColors.first { nav.hue = first.hue }
            nav.install(sortedColors: dominantColors.sorted { $0.hue < $1.hue })
        }
        .onDisappear { nav.remove() }
    }

    private func hueDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private func hexString(_ dc: DominantColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        dc.color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Compact color chip for the horizontal legend

struct WheelColorChip: View {
    let dc: DominantColor
    let near: Bool
    let hex: String
    @State private var copied = false

    private var rgbString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        dc.color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r*255)), \(Int(g*255)), \(Int(b*255)))"
    }
    private var hsbString: String {
        "hsb(\(Int(dc.hue))°, \(Int(dc.saturation*100))%, \(Int(dc.brightness*100))%)"
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(dc.swiftUIColor)
                    .frame(width: 38, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(near ? Color.white : Color(NSColor.separatorColor),
                                lineWidth: near ? 2 : 0.5))
                    .shadow(color: near ? .black.opacity(0.2) : .clear, radius: 3)
                if copied {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 38, height: 38)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            Text(copied ? "已复制" : hex)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .animation(.easeInOut(duration: 0.15), value: copied)
            Text("H\(Int(dc.hue))°")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
            Text("S\(Int(dc.saturation * 100))% V\(Int(dc.brightness * 100))%")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .opacity(near ? 1.0 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: near)
        .onTapGesture { paste(hex) }
        .contextMenu {
            Button("复制 HEX   \(hex)")      { paste(hex) }
            Button("复制 RGB   \(rgbString)") { paste(rgbString) }
            Button("复制 HSB   \(hsbString)") { paste(hsbString) }
        }
        .help("点击复制 HEX · 右键更多格式")
    }

    private func paste(_ str: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

// MARK: - Interactive Wheel (outer ring = hue selector, inner = SB square)

struct InteractiveColorWheelView: View {
    let dominantColors: [DominantColor]
    let colorPoints: [ColorPoint]   // for scatter display in 全色显示 mode
    let dominantOnly: Bool          // false = 全色显示 scatter, true = 主色模式 markers
    @Binding var selectedHue: Double

    private let ringW: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let size  = min(geo.size.width, geo.size.height)
            let cx    = geo.size.width  / 2
            let cy    = geo.size.height / 2
            let outerR = size / 2 - 4
            let innerR = outerR - ringW
            // Largest square inscribed in the inner circle
            let side  = innerR * sqrt(2) * 0.91

            ZStack {
                // ── Outer hue ring ──
                Canvas { ctx, canvasSize in
                    let ccx = canvasSize.width  / 2
                    let ccy = canvasSize.height / 2
                    for i in 0..<360 {
                        let a0 = (Double(i)     - 90) * .pi / 180
                        let a1 = (Double(i + 1) - 90) * .pi / 180
                        let path = Path { p in
                            p.addArc(center: CGPoint(x: ccx, y: ccy), radius: outerR,
                                     startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                            p.addArc(center: CGPoint(x: ccx, y: ccy), radius: innerR,
                                     startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
                            p.closeSubpath()
                        }
                        ctx.fill(path, with: .color(Color(hue: Double(i) / 360.0, saturation: 1, brightness: 1)))
                    }
                }

                // ── Inner SB square ──
                // 全色显示: scatter dots (all colorPoints near this hue)
                // 主色模式: dominant color ring markers only
                SBSquareView(hue: selectedHue,
                             colorPoints: colorPoints,
                             dominantColors: dominantColors,
                             dominantOnly: dominantOnly)
                    .frame(width: side, height: side)
                    .position(x: cx, y: cy)

                // ── Dominant color tick marks on ring ──
                ForEach(dominantColors) { dc in
                    let ang = (dc.hue / 360) * 2 * .pi - .pi / 2
                    let r   = outerR - ringW / 2
                    Circle()
                        .fill(Color(nsColor: dc.color))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .position(x: cx + cos(ang) * r, y: cy + sin(ang) * r)
                }

                // ── Selected hue indicator ──
                let selAng = (selectedHue / 360) * 2 * .pi - .pi / 2
                Circle()
                    .fill(Color(hue: selectedHue / 360, saturation: 1, brightness: 1))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .position(x: cx + cos(selAng) * (outerR - ringW / 2),
                              y: cy + sin(selAng) * (outerR - ringW / 2))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - cx
                        let dy = value.location.y - cy
                        // Only respond when touching the ring area
                        guard sqrt(dx * dx + dy * dy) > innerR * 0.55 else { return }
                        var angle = atan2(dy, dx) + .pi / 2
                        if angle < 0         { angle += 2 * .pi }
                        if angle > 2 * .pi   { angle -= 2 * .pi }
                        selectedHue = angle / (2 * .pi) * 360
                    }
            )
        }
    }
}

// MARK: - Saturation × Brightness square for selected hue
//
// 全色显示 (dominantOnly = false):
//   Full colorPoints scatter filtered to ±22° of the selected hue.
//   Dense dots reveal the actual pixel distribution for this hue slice.
//
// 主色模式 (dominantOnly = true):
//   Only dominant color ring markers (up to 8).
//   Clean view — each dot is a named palette entry.

struct SBSquareView: View {
    let hue: Double
    let colorPoints: [ColorPoint]
    let dominantColors: [DominantColor]
    let dominantOnly: Bool          // false = 全色显示, true = 主色模式

    private let tolerance: Double = 22

    private func hueDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private var filteredPoints: [ColorPoint] {
        colorPoints.filter { hueDiff($0.hue, hue) <= tolerance }
                   .sorted { $0.proportion > $1.proportion }
    }

    private var filteredDominants: [DominantColor] {
        dominantColors.filter { hueDiff($0.hue, hue) <= tolerance }
                      .sorted { $0.proportion > $1.proportion }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // HSB picker gradient for selected hue
                ZStack {
                    LinearGradient(
                        colors: [.white, Color(hue: hue / 360, saturation: 1, brightness: 1)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                }
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5))

                if dominantOnly {
                    // ── 主色模式: dominant color markers only ──
                    if filteredDominants.isEmpty {
                        Text("该色相无主色")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        ForEach(filteredDominants.prefix(8)) { dc in
                            let x = max(10, min(geo.size.width  - 10, dc.saturation * geo.size.width))
                            let y = max(10, min(geo.size.height - 10, (1.0 - dc.brightness) * geo.size.height))
                            ZStack {
                                Circle().fill(Color.black.opacity(0.35)).frame(width: 19, height: 19)
                                Circle().fill(Color.white).frame(width: 16, height: 16)
                                Circle().fill(Color(nsColor: dc.color)).frame(width: 12, height: 12)
                            }
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .position(x: x, y: y)
                        }
                    }
                } else {
                    // ── 全色显示: scatter dots — full colorPoints distribution ──
                    if filteredPoints.isEmpty {
                        Text("该色相无颜色分布")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        ForEach(filteredPoints.prefix(60)) { pt in
                            let x = max(6, min(geo.size.width  - 6, pt.saturation * geo.size.width))
                            let y = max(6, min(geo.size.height - 6, (1.0 - pt.brightness) * geo.size.height))
                            let sz = CGFloat(max(7, min(16, sqrt(pt.proportion) * 140)))
                            ZStack {
                                Circle().fill(Color.black.opacity(0.3)).frame(width: sz + 4, height: sz + 4)
                                Circle().fill(Color.white).frame(width: sz + 2, height: sz + 2)
                                Circle().fill(Color(nsColor: pt.color)).frame(width: sz, height: sz)
                            }
                            .shadow(color: .black.opacity(0.35), radius: 2)
                            .position(x: x, y: y)
                        }
                    }
                }
            }
        }
    }
}
