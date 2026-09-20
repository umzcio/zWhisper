import SwiftUI

/// Design tokens, spec §2.1 (dark theme is the default, spec §1).
enum ZWColor {
    static let surface1 = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let surface2 = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
    static let surface3 = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)
    static let text1 = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
    static let text2 = Color(red: 0x98 / 255, green: 0x98 / 255, blue: 0x9D / 255)
    static let text3 = Color(red: 0x63 / 255, green: 0x63 / 255, blue: 0x66 / 255)
    static let accentBlue = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 1.0)
    static let accentGreen = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    static let accentRed = Color(red: 1.0, green: 0x45 / 255, blue: 0x3A / 255)
    static let accentPurple = Color(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255)
    static let accentTeal = Color(red: 0x64 / 255, green: 0xD2 / 255, blue: 1.0)
    static let accentOrange = Color(red: 1.0, green: 0x9F / 255, blue: 0x0A / 255)
    static let starYellow = Color(red: 1.0, green: 0xD6 / 255, blue: 0x0A / 255)
    static let separator = Color.white.opacity(0.08)
}

/// Hover/press spring feedback per spec §5.2 (SPRING_MICRO, §5.1).
struct ZWButtonStyle: ButtonStyle {    var hoverScale: CGFloat = 1.02
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
