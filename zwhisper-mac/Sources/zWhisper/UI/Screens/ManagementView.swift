import SwiftUI

/// The five management screens (§6). Window sizes per the §6 table.
enum ManagementScreen: String, CaseIterable, Identifiable {
    case modes, history, models, vocabulary, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modes: "Modes"
        case .history: "History"
        case .models: "Models"
        case .vocabulary: "Vocabulary"
        case .settings: "Settings"
        }
    }

    /// §8 sidebar icon map.
    var icon: String {
        switch self {
        case .modes: "square.stack.3d.up"
        case .history: "clock.arrow.circlepath"
        case .models: "cpu"
        case .vocabulary: "text.book.closed"
        case .settings: "gearshape"
        }
    }

    /// §6 window sizes (W×H), minus the 176px sidebar.
    var contentSize: NSSize {
        switch self {
        case .modes: NSSize(width: 960 - 176, height: 640)
        case .history: NSSize(width: 1000 - 176, height: 660)
        case .models: NSSize(width: 1000 - 176, height: 660)
        case .vocabulary: NSSize(width: 960 - 176, height: 640)
        case .settings: NSSize(width: 920 - 176, height: 640)
        }
    }
}

/// Management window shell (§6): 176px SidebarNav (§3.5) + per-screen content.
/// The §3.5 "Dictation" row closes the window and summons the popover (the
/// prototype's "home" has no native window).
struct ManagementView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
                .frame(
                    width: appState.managementScreen.contentSize.width,
                    height: appState.managementScreen.contentSize.height
                )
                .animation(AppState.springDefault, value: appState.managementScreen)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                ZWAppIcon(size: 64)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.bottom, 14)

            SidebarRow(
                icon: "waveform",
                label: "Dictation",
                isActive: false
            ) {
                appState.dismissManagementWindow()
            }
            ForEach(ManagementScreen.allCases) { screen in
                SidebarRow(
                    icon: screen.icon,
                    label: screen.title,
                    isActive: appState.managementScreen == screen
                ) {
                    appState.managementScreen = screen
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 176)
        .frame(maxHeight: .infinity)
        .background(ZWColor.surface2.opacity(0.5))
        .overlay(alignment: .trailing) {
            Rectangle().fill(ZWColor.separator).frame(width: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.managementScreen {
        case .modes: ModesView(appState: appState)
        case .history: HistoryView(appState: appState, embedded: true)
        case .models: ModelsView(appState: appState)
        case .vocabulary: VocabularyView(appState: appState)
        case .settings: SettingsView(appState: appState)
        }
    }
}

/// §3.5 sidebar row: icon 15px + label 13px, radius 6, px 8 py 6; active bg
/// #0A84FF26 + accent icon; inactive text-2, icon text-3, hover surface-3/60.
private struct SidebarRow: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? ZWColor.accentBlue : (hovering ? ZWColor.text1 : ZWColor.text3))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? ZWColor.text1 : (hovering ? ZWColor.text1 : ZWColor.text2))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isActive ? ZWColor.accentBlue.opacity(0.15) : (hovering ? ZWColor.surface3.opacity(0.6) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
