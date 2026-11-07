import Foundation

/// Output check for modes that read screen context (selection, clipboard).
/// That context is written by other people — an email sender, a web page —
/// and the prompt's untrusted-context rule is only advice to the model. So
/// before anything is typed into the user's app, the result is checked for
/// the signs of a steered rewrite; a match is held on the clipboard for the
/// user to read and paste themselves, never auto-pasted.
enum PasteGuard {
    enum Reason: Equatable {
        /// Repeats a stretch of the clipboard the dictation never mentioned.
        case echoesClipboard
        /// Repeats a stretch of the About-you text the dictation never mentioned.
        case echoesPersonalContext
        /// More than one line, headed for a terminal (each line can run).
        case multilineIntoTerminal

        var message: String {
            switch self {
            case .echoesClipboard: "it repeats your clipboard"
            case .echoesPersonalContext: "it repeats your About-you text"
            case .multilineIntoTerminal: "it's several lines going into a terminal"
            }
        }
    }

    /// Shortest verbatim run counted as copying: long enough that ordinary
    /// shared phrases don't trip it, short enough to catch a key or token.
    static let clipboardRun = 24
    /// About-you text is meant to shape signatures and titles, so allow more.
    static let personalContextRun = 48

    /// Terminals: a pasted newline can run a command.
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp",
        "net.kovidgoyal.kitty", "com.mitchellh.ghostty", "io.alacritty", "org.alacritty",
        "co.zeit.hyper", "com.github.wez.wezterm", "org.tabby", "com.raphaelamorim.rio",
    ]

    /// Nil when the output may be pasted; otherwise why it is held. Only
    /// output from a dictation that actually sent screen context is checked.
    static func holdReason(
        output: String,
        raw: String,
        mode: Mode,
        context: CapturedContext?,
        personalContext: String?,
        targetBundleID: String?
    ) -> Reason? {
        guard !mode.isIdentity, let context else { return nil }
        let selection = mode.readsSelectedText ? (context.selectedText ?? "") : ""
        let clipboard = mode.readsClipboard ? (context.clipboard ?? "") : ""
        guard !selection.isEmpty || !clipboard.isEmpty else { return nil }

        if let target = targetBundleID, terminalBundleIDs.contains(target),
           output.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: \.isNewline)
        {
            return .multilineIntoTerminal
        }
        if !clipboard.isEmpty, repeats(clipboard, in: output, unlessIn: raw, run: clipboardRun) {
            return .echoesClipboard
        }
        if let about = personalContext, repeats(about, in: output, unlessIn: raw, run: personalContextRun) {
            return .echoesPersonalContext
        }
        return nil
    }

    /// Whether `output` contains `run` consecutive characters of `source`
    /// (case and spacing ignored) that the dictation itself doesn't contain.
    static func repeats(_ source: String, in output: String, unlessIn raw: String, run: Int) -> Bool {
        let source = normalized(source), output = normalized(output), raw = normalized(raw)
        guard source.count >= run, output.count >= run else { return false }
        var windows = Set<Substring>()
        // Bounded: a huge clipboard can't stall the paste.
        let limited = source.prefix(50_000)
        var start = limited.startIndex
        while let end = limited.index(start, offsetBy: run, limitedBy: limited.endIndex) {
            windows.insert(limited[start..<end])
            start = limited.index(after: start)
        }
        let dictated = Set(windowsOf(raw, run: run))
        return windowsOf(output, run: run).contains { windows.contains($0) && !dictated.contains($0) }
    }

    private static func windowsOf(_ text: String, run: Int) -> [Substring] {
        var result: [Substring] = []
        var start = text.startIndex
        while let end = text.index(start, offsetBy: run, limitedBy: text.endIndex) {
            result.append(text[start..<end])
            start = text.index(after: start)
        }
        return result
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
