import SwiftUI

/// Design tokens, spec §2.1 (dark) / §2.2 (light), resolved dynamically so
/// both themes render correctly (§1: dark-first, light available in Settings).
enum ZWColor {
    static let surface1 = zw(dark: "#1C1C1E", light: "#FFFFFF")
    static let surface2 = zw(dark: "#2C2C2E", light: "#F5F5F7")
    static let surface3 = zw(dark: "#3A3A3C", light: "#E8E8EA")
    static let text1 = zw(dark: "#F5F5F7", light: "#1D1D1F")
    static let text2 = zw(dark: "#98989D", light: "#6E6E73")
    static let text3 = zw(dark: "#636366", light: "#AEAEB2")
    static let accentBlue = zw(dark: "#0A84FF", light: "#007AFF")
    static let accentGreen = zw(dark: "#30D158", light: "#28C840")
    static let accentRed = zw(dark: "#FF453A", light: "#FF3B30")
    static let accentPurple = zw(dark: "#BF5AF2", light: "#AF52DE")
    static let accentTeal = zw(dark: "#64D2FF", light: "#32ADE6")
    static let accentOrange = zw(dark: "#FF9F0A", light: "#FF9500")
    static let starYellow = Color(hex: "#FFD60A")
    static let separator = zwColors(dark: Color.white.opacity(0.08), light: Color.black.opacity(0.08))
}

/// Dynamic dark/light color (§2.1 ↔ §2.2).
private func zwColors(dark: Color, light: Color) -> Color {
    let darkColor = NSColor(dark)
    let lightColor = NSColor(light)
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
    })
}

private func zw(dark: String, light: String) -> Color {
    zwColors(dark: Color(hex: dark), light: Color(hex: light))
}

/// Hover/press spring feedback per spec §5.2 (SPRING_MICRO, §5.1).
struct ZWButtonStyle: ButtonStyle {
    var hoverScale: CGFloat = 1.02
    var pressScale: CGFloat = 0.97

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressScale : (hovering ? hoverScale : 1))
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hovering)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

extension Color {
    /// Mode colors from the §7 script bank (`#RRGGBB`).
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// The real app icon as a view, used wherever the UI shows the zWhisper logo.
struct ZWAppIcon: View {
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}
