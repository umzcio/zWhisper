import SwiftUI

/// Data for the §4.3 result toast.
struct ResultToast: Equatable {
    let words: Int
    let duration: TimeInterval
    /// "Pasted to {app}" when pasted, "Saved to clipboard" when degraded/copy-only.
    let subtitle: String
    /// §4.3: Undo paste only when a real ⌘V paste happened — not the
    /// AX-degraded clipboard-only path, not the auto-paste-off copy path.
    var canUndo: Bool = true
    /// §6.3: Reprocess only when there is a transcript to re-run.
    var canReprocess: Bool = true
    /// Undo paste mutates the text to "Clipboard restored" for 1.8s (§3.7).
    var clipboardRestored = false
}

/// §3.7 home result toast: 288px, radius 14, padding 12, vibrancy + popover
/// shadow + hairline. Enter y 12→0, scale 0.96→1, SPRING_DEFAULT (§5.1).
struct ResultToastView: View {
    let toast: ResultToast
    let onUndo: () -> Void
    let onReprocess: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic")
                .font(.system(size: 13))
                .foregroundStyle(ZWColor.accentTeal)
                .frame(width: 28, height: 28)
                .background(ZWColor.accentTeal.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.clipboardRestored ? "Clipboard restored" : "Saved to History")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ZWColor.text1)
                Text(toast.clipboardRestored
                    ? toast.subtitle
                    : "\(toast.subtitle) · \(toast.words) words · \(Self.formatDuration(toast.duration))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ZWColor.text2)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !toast.clipboardRestored {
                // §4.3 toast buttons: Reprocess / Undo paste (only when the
                // flow actually produced something for them to act on).
                if toast.canReprocess {
                    Button("Reprocess", action: onReprocess)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ZWColor.text2)
                        .buttonStyle(ZWButtonStyle(pressScale: 0.96))
                }
                if toast.canUndo {
                    Button("Undo paste", action: onUndo)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ZWColor.accentBlue)
                        .buttonStyle(ZWButtonStyle(pressScale: 0.96))
                }
            }
        }
        .padding(12)
        .background(
            ZWColor.surface2.opacity(0.8)
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ZWColor.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 32, y: 24)
    }

    /// §4.3 meta: `{m:ss}`.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let rest = Int(seconds.rounded()) % 60
        return String(format: "%d:%02d", minutes, rest)
    }
}
