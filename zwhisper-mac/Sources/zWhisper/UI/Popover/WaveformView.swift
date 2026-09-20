import SwiftUI

/// Live popover waveform (spec §3.2): 48/28 bars, 4px wide, 6px gap, centered
/// as a group (clipping like the prototype's canvas), corner radius
/// min(4, w/2, h/2), heights symmetric about the vertical center. Fed by real
/// RMS from the audio tap (architecture §5) via AppState.currentLevel.
struct WaveformView: View {
    let appState: AppState
    /// 48 bars (Main) / 28 bars (Mini) per spec §3.1; 34 for the docked pill.
    let barCount: Int
    /// Docked indicator: clean white bars instead of the §2.6 gradient.
    var monochrome = false

    private var isRecording: Bool {
        if case .recording = appState.phase { return true }
        return false
    }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { graphics, size in
                let now = context.date
                let heights = appState.waveform.update(
                    barCount: barCount,
                    maxHeight: size.height,
                    level: appState.currentLevel,
                    now: now,
                    reduceMotion: AppState.reduceMotion
                )

                if isRecording, !AppState.reduceMotion {
                    drawGlow(in: &graphics, size: size, now: now)
                }

                let totalWidth = CGFloat(barCount) * 4 + CGFloat(barCount - 1) * 6
                let originX = (size.width - totalWidth) / 2
                let shading: GraphicsContext.Shading
                if monochrome {
                    shading = .color(isRecording || appState.waveform.state == .settling ? ZWColor.text1 : ZWColor.text3)
                } else if isRecording || appState.waveform.state == .settling {
                    // §2.6 recording gradient: #30D158 → #64D2FF, left → right
                    shading = .linearGradient(
                        Gradient(colors: [ZWColor.accentGreen, ZWColor.accentTeal]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    )
                } else {
                    shading = .color(ZWColor.text3)
                }

                var path = Path()
                for (index, height) in heights.enumerated() {
                    let rect = CGRect(
                        x: originX + CGFloat(index) * 10,
                        y: (size.height - height) / 2,
                        width: 4,
                        height: height
                    )
                    path.addRoundedRect(
                        in: rect,
                        cornerSize: CGSize(width: min(4, 2, height / 2), height: min(4, 2, height / 2)),
                        style: .continuous
                    )
                }
                graphics.fill(path, with: shading)
            }
        }
        .clipped()
    }

    /// §2.6 recording glow: radial gradient rgba(48,209,88,0.25) → transparent,
    /// breathing scale 1→1.06 / opacity 0.9→1 on a 2s ease-in-out cycle.
    private func drawGlow(in graphics: inout GraphicsContext, size: CGSize, now: Date) {
        let phase = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 2) / 2
        let breath = 0.5 - 0.5 * cos(2 * .pi * phase) // ease-in-out 0→1→0 over 2s
        let scale = 1 + 0.06 * breath
        let opacity = 0.9 + 0.1 * breath
        let radius = min(size.width, size.height) / 2 * scale
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        graphics.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [ZWColor.accentGreen.opacity(0.25 * opacity), .clear]),
                center: center,
                startRadius: 0,
                endRadius: max(radius, 1)
            )
        )
    }
}
