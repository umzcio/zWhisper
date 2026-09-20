import AppKit
import ApplicationServices

/// Architecture §3.6.
struct PasteReceipt: Sendable {
    /// Pasteboard changeCount after our write (diagnostics, §3.6).
    let changeCount: Int
    /// Full pre-paste clipboard archive for Undo paste (§4.3).
    let snapshot: [NSPasteboard.PasteboardType: Data]
    /// Frontmost app at paste time, for "Pasted to {app}" (§4.3).
    let targetApp: String
    /// False when Accessibility is missing and we degraded to clipboard-only (§8).
    let didPaste: Bool
}

enum PasteError: Error {
    case clipboardWriteFailed
}

/// Architecture §3.6 contract.
protocol PasteControllerProtocol: Sendable {
    func paste(text: String, restoreClipboard: Bool) async throws -> PasteReceipt
    /// "Undo paste" (§4.3): restores the pre-paste clipboard snapshot. We
    /// deliberately do not try to delete text from the target app (§3.6).
    func undo(_ receipt: PasteReceipt) async
    /// Auto-paste off (§6.6): result goes to the clipboard without ⌘V.
    func copy(text: String) async
}

/// Full paste sequence (architecture §8): snapshot the clipboard → write the
/// transcript → read the frontmost app for the toast label → post CGEvent ⌘V →
/// give the target one poll cycle to read → restore the snapshot when Settings
/// → Paste "Restore clipboard" is on.
@MainActor
final class PasteController: PasteControllerProtocol {
    /// Accessibility prompt is shown at most once per launch (§8).
    private var didPromptForAccessibility = false

    func paste(text: String, restoreClipboard: Bool) async throws -> PasteReceipt {
        let pasteboard = NSPasteboard.general
        let snapshot = Self.snapshot(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw PasteError.clipboardWriteFailed
        }
        let changeCount = pasteboard.changeCount

        let targetApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let trusted = AXIsProcessTrusted()
        if !trusted, !didPromptForAccessibility {
            didPromptForAccessibility = true
            // Literal key: kAXTrustedCheckOptionPrompt is a C var (not concurrency-safe).
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        var didPaste = false
        if trusted {
            Self.postCommandV()
            didPaste = true
            // One poll cycle for the target app to read the pasteboard (§8).
            try? await Task.sleep(for: .milliseconds(250))
        }

        // Restore only after a real paste; when degraded (§8) the transcript
        // must stay on the clipboard so the user can ⌘V manually.
        if restoreClipboard, didPaste {
            Self.restore(snapshot, to: pasteboard)
        }
        return PasteReceipt(changeCount: changeCount, snapshot: snapshot, targetApp: targetApp, didPaste: didPaste)
    }

    func undo(_ receipt: PasteReceipt) async {
        Self.restore(receipt.snapshot, to: .general)
    }

    func copy(text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType: Data] {
        var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
        }
        return snapshot
    }

    private static func restore(_ snapshot: [NSPasteboard.PasteboardType: Data], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let item = NSPasteboardItem()
        for (type, data) in snapshot {
            item.setData(data, forType: type)
        }
        pasteboard.writeObjects([item])
    }

    /// ⌘V as a hardware-sourced keyboard event (§8).
    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
