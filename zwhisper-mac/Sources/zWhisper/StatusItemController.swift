import AppKit

/// NSStatusItem menu extra (spec §3.3, architecture §2). Left click toggles
/// the recording popover; right click shows the app menu (History / Settings /
/// Quit), the standard menu-bar-app pattern.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = 27
        if let button = statusItem.button {
            button.image = NSImage(named: "zMenubarIcon")
            button.image?.size = NSSize(width: 19, height: 19)
            button.image?.isTemplate = true
            button.image?.accessibilityDescription = "zWhisper"
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let entries: [(String, ManagementScreen)] = [
            ("Modes…", .modes),
            ("History…", .history),
            ("Models…", .models),
            ("Vocabulary…", .vocabulary),
            ("Settings…", .settings),
        ]
        for (title, screen) in entries {
            let item = NSMenuItem(title: title, action: #selector(menuScreen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = screen.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(menuUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        let quit = NSMenuItem(title: "Quit zWhisper", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Swapping the menu in for one click keeps left-click toggle behavior.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuScreen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let screen = ManagementScreen(rawValue: raw)
        else { return }
        WindowActions.showManage(screen)
    }

    @objc private func menuUpdates() {
        UpdateController.checkForUpdates()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
