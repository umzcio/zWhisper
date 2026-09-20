import AppKit
import ApplicationServices

/// Architecture §3.7: captures frontmost app identity, selected text (AX), and
/// clipboard (only when the mode asks for it). Runs in parallel with recording
/// start against the §7 CONTEXT_MS budget (600ms); the context dot (§3.1)
/// lights when capture lands. AX reads get a timeout and never hard-fail
/// (§10.2: Electron/browsers expose focused-element AX inconsistently).
enum ContextCapture {
    /// Real deadline for the §7 CONTEXT_MS budget.
    static let deadline: Duration = .milliseconds(600)

    static func capture(readSelectedText: Bool, readClipboard: Bool) async -> CapturedContext? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let appName = frontmost?.localizedName ?? ""
        let bundleID = frontmost?.bundleIdentifier ?? ""
        guard !appName.isEmpty || !bundleID.isEmpty else { return nil }

        async let selected: String? = readSelectedText ? Self.selectedText() : nil
        let clipboard = readClipboard ? NSPasteboard.general.string(forType: .string) : nil

        return CapturedContext(
            frontmostApp: bundleID.isEmpty ? appName : "\(bundleID) · \(appName)",
            selectedText: await selected,
            clipboard: clipboard,
            capturedAt: .now
        )
    }

    /// AXSelectedText of the focused element (§3.7). Nil when AX is untrusted
    /// or the element doesn't expose a selection — never throws (§10.2).
    private static func selectedText() async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var element: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    AXUIElementCreateSystemWide(),
                    kAXFocusedUIElementAttribute as CFString,
                    &element
                ) == .success, let element else { return nil }
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    element as! AXUIElement,
                    kAXSelectedTextAttribute as CFString,
                    &value
                ) == .success else { return nil }
                return value as? String
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
