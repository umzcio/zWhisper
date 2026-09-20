import SwiftUI

/// Docked bottom-right indicator (SuperWhisper-style). Two calm states instead
/// of the full popover chrome: a tiny rest pill (mode glyph + a few quiet
/// bars — tap to record, glyph opens the mode switcher) and an expanded
/// recording pill (red record button + clean white live waveform, cancel on
/// hover). Monochrome on vibrancy; no pills, labels, or chevrons.
struct DockedIndicatorView: View {
    let appState: AppState

    @State private var hovering = false

    /// Recording and everything after it keeps the expanded frame.
    private var isActive: Bool {
        switch appState.phase {
        case .idle: return false
        case .recording, .transcribing, .processing, .pasting, .pasted: return true
        }
    }

    private var isBusy: Bool {
        switch appState.phase {
        case .transcribing, .processing, .pasting: return true
        case .idle, .recording, .pasted: return false
        }
    }

    private var isPasted: Bool {
        if case .pasted = appState.phase { return true }
        return false
    }

    var body: some View {
        Group {
            if isActive {
                recordingRow
            } else {
                restRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    // MARK: Rest — tiny pill: glyph + quiet bars. Tap body to record.

    private var restRow: some View {
        HStack(spacing: 10) {
            Button { appState.toggleSwitcher() } label: {
                Image(systemName: appState.activeMode.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: appState.activeMode.colorHex))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ZWButtonStyle(hoverScale: 1.08, pressScale: 0.92))
            .help("\(appState.activeMode.name) — change mode")

            QuietBars()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { appState.startDictation() }
        .help("Dictate")
    }

    // MARK: Recording — record button + live white waveform + hover cancel

    private var recordingRow: some View {
        HStack(spacing: 12) {
            Button(action: appState.stopDictation) {
                Image(systemName: "square.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(isBusy ? ZWColor.accentRed.opacity(0.4) : ZWColor.accentRed)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(ZWButtonStyle(hoverScale: 1.06, pressScale: 0.94))
            .disabled(isBusy)
            .help("Stop")

            WaveformView(appState: appState, barCount: 34, monochrome: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 6)

            if isPasted {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ZWColor.accentGreen)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Button(action: appState.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13))
                        .foregroundStyle(ZWColor.text2)
                        .frame(width: 26, height: 26)
                        .background(hovering ? ZWColor.surface3 : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(ZWButtonStyle(hoverScale: 1.08, pressScale: 0.94))
                .disabled(isBusy)
                .opacity(isBusy ? 0.4 : (hovering ? 1 : 0))
                .offset(x: hovering ? 0 : 16)
                .help("Cancel")
            }
        }
        .padding(.horizontal, 12)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hovering)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: appState.phase)
    }
}

/// Seven tiny static bars for the rest pill — quiet, no animation.
private struct QuietBars: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(ZWColor.text1.opacity(0.45))
                    .frame(width: 3, height: height(for: i))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func height(for index: Int) -> CGFloat {
        4 + abs(sin(Double(index) * 0.9)) * 10
    }
}
