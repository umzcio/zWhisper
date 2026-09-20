import AppKit
import ApplicationServices
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Spec §4.1: toggle recording.
    static let toggleRecording = Self("toggleRecording", default: .init(.space, modifiers: [.option, .shift]))
    /// Spec §4.2: cancel (Esc works in every phase).
    static let cancelDictation = Self("cancelDictation", default: .init(.escape))
    /// §3.5 push-to-talk. No default: hold right ⌘ out of the box (modifier
    /// keys can't be expressed as a KeyboardShortcuts default); a key recorded
    /// here overrides the PTT key.
    static let pushToTalk = Self("pushToTalk")
    /// §3.5: change mode (cycle), ⌥⇧K.
    static let changeModeCycle = Self("changeModeCycle", default: .init(.k, modifiers: [.option, .shift]))
    /// §4.2: ⌘1–⌘7 live mode select (built-in library indices).
    static let modeDigit1 = Self("modeDigit1", default: .init(.one, modifiers: [.command]))
    static let modeDigit2 = Self("modeDigit2", default: .init(.two, modifiers: [.command]))
    static let modeDigit3 = Self("modeDigit3", default: .init(.three, modifiers: [.command]))
    static let modeDigit4 = Self("modeDigit4", default: .init(.four, modifiers: [.command]))
    static let modeDigit5 = Self("modeDigit5", default: .init(.five, modifiers: [.command]))
    static let modeDigit6 = Self("modeDigit6", default: .init(.six, modifiers: [.command]))
    static let modeDigit7 = Self("modeDigit7", default: .init(.seven, modifiers: [.command]))

    static let modeDigits: [KeyboardShortcuts.Name] = [
        modeDigit1, modeDigit2, modeDigit3, modeDigit4, modeDigit5, modeDigit6, modeDigit7,
    ]
}

/// Global hotkeys (architecture §3.5). Toggle-style bindings via
/// KeyboardShortcuts; PTT hold (NSEvent monitors) arrives in M7.
@MainActor
final class HotkeyManager {
    func setUp(
        onToggleRecording: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onCycleMode: @escaping @MainActor () -> Void,
        onModeDigit: @escaping @MainActor (Int) -> Void
    ) {
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) {
            Task { @MainActor in onToggleRecording() }
        }
        KeyboardShortcuts.onKeyDown(for: .cancelDictation) {
            Task { @MainActor in onCancel() }
        }
        KeyboardShortcuts.onKeyDown(for: .changeModeCycle) {
            Task { @MainActor in onCycleMode() }
        }
        for (index, name) in KeyboardShortcuts.Name.modeDigits.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) {
                Task { @MainActor in onModeDigit(index + 1) }
            }
        }
        // ⌘-digits start unclaimed: they are only registered while the popover
        // is open, so iTerm/Chrome keep their tab shortcuts otherwise (§4.2
        // uses them "while recording" anyway).
        setModeDigitsEnabled(false)
        // Esc starts unclaimed for the same reason, but more critically: a
        // permanently-registered bare Esc steals Escape from every app
        // system-wide. It is claimed only while the popover is open (§4.2:
        // "Esc while popover open → cancel").
        setCancelDictationEnabled(false)
    }

    /// Claims/releases the bare Esc hotkey. While we hold it, Escape is
    /// exclusively ours — acceptable only while the popover is visibly up
    /// (recording/cancelling); with the popover closed, Esc belongs to the OS.
    func setCancelDictationEnabled(_ enabled: Bool) {
        if enabled {
            KeyboardShortcuts.reset([.cancelDictation])
        } else {
            KeyboardShortcuts.setShortcut(nil, for: .cancelDictation)
        }
    }

    /// Claims/releases ⌘1–⌘7 globally. Carbon hotkeys are exclusive — while we
    /// hold them, frontmost apps never see the events — so we only hold them
    /// when a mode switch is actually possible (popover open).
    func setModeDigitsEnabled(_ enabled: Bool) {
        for name in KeyboardShortcuts.Name.modeDigits {
            if enabled {
                KeyboardShortcuts.reset([name])
            } else {
                KeyboardShortcuts.setShortcut(nil, for: name)
            }
        }
    }

    // MARK: Push-to-talk (architecture §3.5)

    /// kVK_RightCommand — the PTT default. A modifier-only key, so it arrives
    /// as flagsChanged, and it types nothing (no editable-focus guard needed,
    /// which is why it beats Space as the default).
    private static let rightCommandKeyCode: UInt16 = 54

    private var pttHeld = false

    /// Hand-rolled PTT (KeyboardShortcuts never reports key-up, §3.5). Hold
    /// right ⌘ (or a custom key recorded in Settings → Shortcuts) to dictate;
    /// release to stop + paste. §10.1 mitigations: any other key while held is
    /// an implicit release, and the active-duration cap bounds a stuck hold.
    func setUpPushToTalk(
        onStart: @escaping @MainActor () -> Void,
        onStop: @escaping @MainActor () -> Void
    ) {
        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self, event.keyCode == Self.rightCommandKeyCode else { return }
            // Right ⌘ pressed vs released: the .command flag flips with it.
            if event.modifierFlags.contains(.command) {
                self.pttPress(onStart)
            } else {
                self.pttRelease(onStop)
            }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return }
            let customKey = KeyboardShortcuts.getShortcut(for: .pushToTalk)
            if let customKey, event.keyCode == customKey.carbonKeyCode {
                if event.type == .keyDown, !event.isARepeat {
                    // §10.1: a character-typing PTT key must not fire while a text
                    // field is editable (it would type). Right ⌘ types nothing and
                    // skips this guard; without AX trust the guard can't run and
                    // custom-key PTT stays disabled.
                    guard !Self.focusedElementIsEditable() else { return }
                    self.pttPress(onStart)
                } else if event.type == .keyUp {
                    self.pttRelease(onStop)
                }
                return
            }
            // §10.1: any other key while held = implicit release (no stuck hold).
            if self.pttHeld, event.type == .keyDown {
                self.pttRelease(onStop)
            }
        }
        // Same handling when our own app is key (e.g. the mode pill).
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self, event.keyCode == Self.rightCommandKeyCode else { return event }
            if event.modifierFlags.contains(.command) {
                self.pttPress(onStart)
            } else {
                self.pttRelease(onStop)
            }
            return event
        }
    }

    private func pttPress(_ action: @escaping @MainActor () -> Void) {
        guard !pttHeld else { return }
        pttHeld = true
        Task { @MainActor in action() }
    }

    /// §10.1 editable-focus guard: true when the frontmost app's focused
    /// element is a text-ish control. Without Accessibility trust we can't
    /// know — return true so custom character keys stay disabled (degraded).
    private static func focusedElementIsEditable() -> Bool {
        guard AXIsProcessTrusted() else { return true }
        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &element
        ) == .success, let element else { return false }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXRoleAttribute as CFString,
            &role
        ) == .success, let role = role as? String else { return false }
        return [
            kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField", "AXSecureTextField",
        ].contains(role)
    }

    private func pttRelease(_ action: @escaping @MainActor () -> Void) {
        guard pttHeld else { return }
        pttHeld = false
        Task { @MainActor in action() }
    }
}
