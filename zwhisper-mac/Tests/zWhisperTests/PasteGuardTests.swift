import Foundation
import Testing
@testable import zWhisper

@Suite("PasteGuard (review before paste)")
struct PasteGuardTests {
    private func context(selection: String?, clipboard: String?) -> CapturedContext {
        CapturedContext(frontmostApp: "com.apple.mail · Mail", selectedText: selection, clipboard: clipboard, capturedAt: .now)
    }

    @Test("review whenever the mode actually sent the selection or clipboard")
    func sentContext() {
        // Email reads the selection.
        #expect(PasteGuard.requiresReview(mode: BuiltInModes.email, context: context(selection: "thread", clipboard: nil)))
        // Super Mode reads both; a short clipboard alone is enough.
        #expect(PasteGuard.requiresReview(mode: BuiltInModes.superMode, context: context(selection: nil, clipboard: "1234")))
    }

    @Test("no review when nothing from the screen reached the model")
    func noContextSent() {
        #expect(!PasteGuard.requiresReview(mode: BuiltInModes.email, context: nil))
        #expect(!PasteGuard.requiresReview(mode: BuiltInModes.email, context: context(selection: "", clipboard: nil)))
        // Email doesn't read the clipboard, so a clipboard alone sent nothing.
        #expect(!PasteGuard.requiresReview(mode: BuiltInModes.email, context: context(selection: nil, clipboard: "secret")))
        // Modes without context flags, and Voice Note (no model), never wait.
        #expect(!PasteGuard.requiresReview(mode: BuiltInModes.message, context: context(selection: "x", clipboard: "y")))
        #expect(!PasteGuard.requiresReview(mode: BuiltInModes.voiceNote, context: context(selection: "x", clipboard: "y")))
    }
}
