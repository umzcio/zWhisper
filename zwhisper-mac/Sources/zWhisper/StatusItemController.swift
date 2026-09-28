import AppKit
import SwiftUI

/// NSStatusItem menu extra (spec §3.3, architecture §2). Left click opens an
/// NSPopover anchored to the icon — the exact zMeet mechanism (`.transient` +
/// `animates`), so open/close uses Apple's built-in popover animation.
/// Right click shows the classic NSMenu (screen links, updates, Quit).
/// The icon never starts recording on its own.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(appState: AppState) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = 26
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(named: "zMenubarIcon")
            button.image?.size = NSSize(width: 20, height: 20)
            button.image?.isTemplate = true
            button.image?.accessibilityDescription = "zWhisper"
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(
            rootView: MenubarPanelView(appState: appState) { [weak self] in
                self?.popover.performClose(nil)
            }
        )
        popover.contentViewController = host
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showLegacyMenu()
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // zMeet parity: an accessory app must activate and the popover must
            // become key, or .transient never engages and outside clicks don't
            // dismiss it.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// The classic NSMenu (right click): screen links, updates, Quit.
    private func showLegacyMenu() {
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
