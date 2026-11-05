import Foundation

/// Fits a dictation to the text already before the caret, so consecutive
/// dictations read as one document: "…the moon." + "Then…" gets its space, a
/// new sentence gets its capital, and a continuation drops the capital the
/// transcriber gives every utterance.
enum SmartJoin {
    /// A closed list, not a dictionary check: the system spell checker accepts
    /// "zach" and "paris", so it can't protect names from being lowercased.
    private static let continuationWords: Set<String> = [
        "a", "also", "an", "and", "are", "as", "at", "because", "but", "by",
        "for", "from", "he", "if", "in", "is", "it", "not", "of", "on", "or",
        "she", "so", "that", "the", "then", "there", "these", "they", "this",
        "those", "to", "was", "we", "were", "when", "which", "while", "with", "you",
    ]
    private static let noSpaceAfter = Set("([{<“‘-–—/@#$~\\")
    private static let noSpaceBefore = Set(".,;:!?)]}%…”’")
    private static let sentenceEnders = Set(".!?…")
    private static let closers = Set(")]}\"'”’")

    /// `preceding` is the text before the caret: nil when unknown (the text is
    /// left alone), empty at the start of a field.
    static func adjust(_ text: String, preceding: String?) -> String {
        guard let preceding, let first = text.first, !first.isWhitespace else { return text }
        let cased: String
        switch position(after: preceding) {
        case .sentenceStart: cased = capitalizingFirstWord(text)
        case .midSentence: cased = loweringContinuationWord(text)
        case .unknown: cased = text
        }
        return needsSpace(after: preceding, before: first) ? " " + cased : cased
    }

    /// True when nothing has moved the caret since a paste `elapsed` seconds
    /// ago. Slack covers the posted ⌘V landing just after the paste was stamped.
    static func isCaretUnmoved(elapsed: TimeInterval, sinceKeyDown: TimeInterval, sinceClick: TimeInterval) -> Bool {
        min(sinceKeyDown, sinceClick) + 0.25 >= elapsed
    }

    private enum Position { case sentenceStart, midSentence, unknown }

    private static func position(after preceding: String) -> Position {
        guard let end = preceding.lastIndex(where: { !$0.isWhitespace }) else { return .sentenceStart }
        if preceding[end...].contains(where: \.isNewline) { return .sentenceStart }
        let body = preceding[...end]
        if let core = body.last(where: { !closers.contains($0) }), sentenceEnders.contains(core) {
            return .sentenceStart
        }
        let last = preceding[end]
        return last.isLetter || last.isNumber || last == "," || last == ";" ? .midSentence : .unknown
    }

    private static func needsSpace(after preceding: String, before first: Character) -> Bool {
        guard let last = preceding.last, !last.isWhitespace, !noSpaceBefore.contains(first) else { return false }
        if last == "\"" || last == "'" {
            // A straight quote opens when it follows whitespace, closes otherwise.
            guard let beforeQuote = preceding.dropLast().last else { return false }
            return !beforeQuote.isWhitespace
        }
        return !noSpaceAfter.contains(last)
    }

    private static func capitalizingFirstWord(_ text: String) -> String {
        let word = text.prefix(while: \.isLetter)
        // "iPhone" keeps its casing.
        guard let first = word.first, first.isLowercase, !word.contains(where: \.isUppercase) else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func loweringContinuationWord(_ text: String) -> String {
        let word = String(text.prefix(while: \.isLetter))
        guard continuationWords.contains(word.lowercased()), word == word.capitalized else { return text }
        return word.lowercased() + text.dropFirst(word.count)
    }
}
