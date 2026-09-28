import AppKit
import SwiftUI

/// Menu-bar popover content (§3.3): Dictate row, quick mode toggle list,
/// bottom bar (Open / Settings / Quit). Presented by StatusItemController in
/// an NSPopover (the zMeet mechanism), so the arrow, transient dismissal, and
/// open/close animation are Apple's built-ins.
struct MenubarPanelView: View {
    @Bindable var appState: AppState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                close()
                appState.dictateFromMenu()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Dictate")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("hold right ⌘")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(ZWColor.accentRed)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(ZWButtonStyle(pressScale: 0.97))
            .padding(10)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(appState.modes) { mode in
                    modeRow(mode)
                }
            }
            .padding(.horizontal, 6)

            bottomBar
        }
        .frame(width: 264)
        .padding(.bottom, 8)
    }

    private func modeRow(_ mode: Mode) -> some View {
        Button {
            appState.setActiveMode(mode)
            close()
        } label: {
            ModeRowLabel(mode: mode, isActive: mode.id == appState.activeMode.id)
        }
        .buttonStyle(.plain)
    }

    /// Row label with hover feedback (100ms) and a 120ms crossfade when the
    /// active-mode indicator moves — near-imperceptible at panel frequency.
    private struct ModeRowLabel: View {
        let mode: Mode
        let isActive: Bool
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: mode.colorHex))
                    .frame(width: 16)
                Text(mode.name)
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text1)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ZWColor.accentBlue)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isActive
                    ? ZWColor.accentBlue.opacity(0.12)
                    : (hovering ? ZWColor.surface3.opacity(0.6) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
            .animation(.easeOut(duration: 0.12), value: isActive)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Button {
                close()
                WindowActions.showManage(appState.managementScreen)
            } label: {
                Text("Open")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ZWColor.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(ZWColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(ZWButtonStyle(pressScale: 0.97))
            Button {
                close()
                WindowActions.showManage(.settings)
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundStyle(ZWColor.text2)
                    .frame(width: 28, height: 28)
                    .background(ZWColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(ZWButtonStyle(pressScale: 0.97))
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ZWColor.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(ZWColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(ZWButtonStyle(pressScale: 0.97))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}
