import Foundation

/// Paste policy for modes that read screen context (selection, clipboard).
///
/// That context is written by other people — an email sender, a web page, a
/// log line — and the prompt's untrusted-context rule is only advice to the
/// model. Spotting a steered result after the fact doesn't work: a coaxed
/// command or a disguised clipboard secret has no reliable signature, and the
/// target (a shell inside an IDE, an SSH client, a web terminal) can't be
/// told from a text field. So whenever a dictation actually sent screen
/// context to the model, its result is shown for review and typed only when
/// the user presses Return. Everything else pastes at once, as before.
enum PasteGuard {
    static func requiresReview(mode: Mode, context: CapturedContext?) -> Bool {
        guard !mode.isIdentity, let context else { return false }
        let sentSelection = mode.readsSelectedText && !(context.selectedText ?? "").isEmpty
        let sentClipboard = mode.readsClipboard && !(context.clipboard ?? "").isEmpty
        return sentSelection || sentClipboard
    }
}
