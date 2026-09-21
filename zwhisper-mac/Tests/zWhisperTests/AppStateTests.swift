import AppKit
import Foundation
import Testing
@testable import zWhisper

@Suite("AppState popover (M1)")
@MainActor
struct AppStateTests {
    @Test("summon/dismiss toggles open state and plays the entrance")
    func summonDismiss() async throws {
        let state = AppState()
        #expect(!state.isPopoverOpen)

        state.summonPopover()
        #expect(state.isPopoverOpen)
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.popoverAppeared)

        state.dismissPopover()
        #expect(!state.isPopoverOpen)
        #expect(!state.popoverAppeared)
    }

    @Test("toggle flips between summon and dismiss")
    func toggle() {
        let state = AppState()
        state.togglePopover()
        #expect(state.isPopoverOpen)
        state.togglePopover()
        #expect(!state.isPopoverOpen)
    }

    @Test("Esc cancel shakes and closes at 420ms; ignored when closed")
    func cancel() async throws {
        let state = AppState()
        state.cancel()
        #expect(state.cancelShakeTrigger == 0)

        state.summonPopover()
        state.cancel()
        #expect(state.cancelShakeTrigger == 1)
        #expect(state.isPopoverOpen)

        try await Task.sleep(for: .milliseconds(600))
        #expect(!state.isPopoverOpen)
    }

    @Test("size toggle flips Main ↔ Mini")
    func sizeToggle() {
        let state = AppState()
        #expect(state.popoverSize == .main)
        state.togglePopoverSize()
        #expect(state.popoverSize == .mini)
        state.togglePopoverSize()
        #expect(state.popoverSize == .main)
    }

    @Test("⌘-digit hotkeys are claimed only while the popover is open")
    func digitHotkeyGating() {
        let state = AppState()
        var calls: [Bool] = []
        state.setModeDigitsEnabled = { calls.append($0) }
        state.summonPopover()
        #expect(calls == [true])
        state.dismissPopover()
        #expect(calls == [true, false])
    }

    @Test("docked indicator: dismiss collapses instead of hiding")
    func dockedCollapse() {
        let state = AppState()
        state.settings.popoverPlacement = .bottomRight
        state.summonPopover()
        #expect(state.isPopoverOpen)
        state.dismissPopover()
        #expect(!state.isPopoverOpen)
        #expect(state.isDocked)
    }

    @Test("cancel shortcut stores and round-trips; default is esc")
    func cancelShortcutStorage() {
        #expect(CancelShortcut.current == .escape)
        let custom = CancelShortcut(keyCode: 40, modifiers: Int(NSEvent.ModifierFlags.shift.union(.option).rawValue))
        CancelShortcut.store(custom)
        #expect(CancelShortcut.current == custom)
        UserDefaults.standard.removeObject(forKey: "zw.cancelShortcut")
        #expect(CancelShortcut.current == .escape)
    }
}
