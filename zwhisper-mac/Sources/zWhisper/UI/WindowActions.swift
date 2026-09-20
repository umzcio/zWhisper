import SwiftUI

/// Bridges the SwiftUI `openWindow` action out of the scene tree so AppKit
/// code (the status-item menu) can open management windows.
@MainActor
enum WindowActions {
    static var openWindow: OpenWindowAction?
    static weak var appState: AppState?

    static func showManage(_ screen: ManagementScreen) {
        appState?.managementScreen = screen
        if let openWindow {
            openWindow(id: "manage")
        } else if let window = NSApp.windows.first(where: { $0.title == "zWhisper" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            FileHandle.standardError.write(Data("[zWhisper] showManage: no openWindow bridge and no window\n".utf8))
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func showHistory() {
        showManage(.history)
    }

    static func showSettings() {
        showManage(.settings)
    }
}
