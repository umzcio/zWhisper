import Foundation

/// Paste policy for modes that read screen context (selection, clipboard).
///
/// That context is written by other people — an email sender, a web page, a
/// log line — and the prompt's untrusted-context rule is only advice to the
/// model. Spotting a steered result after the fact doesn't work: a coaxed
/// command or a disguised clipboard secret has no reliable signature, and the
/// target (a shell inside an IDE, an SSH client, a web terminal) can't be
/// told from a text field. So whenever a dictation actually sent screen
/// context to the model, its result is shown in full for review and typed
/// only when the user presses Return. Everything else pastes at once.
enum PasteGuard {
    /// Which kinds of screen context a dictation actually sent to the model.
    struct SentContext: Equatable {
        var selection = false
        var clipboard = false
        var any: Bool { selection || clipboard }
    }

    static func sentContext(mode: Mode, context: CapturedContext?) -> SentContext {
        guard !mode.isIdentity, let context else { return SentContext() }
        return SentContext(
            selection: mode.readsSelectedText && !(context.selectedText ?? "").isEmpty,
            clipboard: mode.readsClipboard && !(context.clipboard ?? "").isEmpty
        )
    }

    static func requiresReview(mode: Mode, context: CapturedContext?) -> Bool {
        sentContext(mode: mode, context: context).any
    }

    /// The pending result as the review shows it: one entry per line the
    /// target app will see, so nothing typed can hide past a line break, and
    /// every scalar that would draw nothing, draw blank, or reorder text
    /// replaced by a visible marker.
    struct Review: Equatable {
        var lines: [String] = []
        /// Scalars drawn as markers: present in the paste, invisible as text.
        var hidden = 0
        /// Every scalar that will be typed (graphemes would hide attached ones).
        var scalars = 0
    }

    static func review(_ text: String) -> Review {
        let scalars = Array(text.unicodeScalars)
        var result = Review(scalars: scalars.count)
        var current = String.UnicodeScalarView()
        // Emoji context: one presentation selector may follow an emoji, and
        // a joiner may follow the emoji or its selector. Anything more would
        // be an invisible channel.
        var selectorAllowed = false
        var joinerAllowed = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            defer { index += 1 }
            // Every line terminator splits: CR alone acts as Return in a terminal.
            if isLineBreak(scalar) {
                if scalar.value == 0x0D, index + 1 < scalars.count, scalars[index + 1].value == 0x0A {
                    index += 1 // CRLF is one break
                }
                result.lines.append(String(current))
                current = String.UnicodeScalarView()
                selectorAllowed = false
                joinerAllowed = false
                continue
            }
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            let isSelector = (0xFE0E ... 0xFE0F).contains(scalar.value)
            let allowed = isSelector ? selectorAllowed : scalar.value == 0x200D ? joinerAllowed && isPictographic(next) : false
            if let marker = marker(for: scalar, emojiPart: allowed) {
                result.hidden += 1
                current.append(contentsOf: marker.unicodeScalars)
                selectorAllowed = false
                joinerAllowed = false
            } else {
                current.append(scalar)
                selectorAllowed = isPictographic(scalar)
                joinerAllowed = isPictographic(scalar) || (isSelector && allowed)
            }
        }
        result.lines.append(String(current))
        return result
    }

    static func reviewLines(_ text: String) -> [String] {
        review(text).lines
    }

    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: return true
        default: return false
        }
    }

    /// Decided by Unicode properties, not a list, so code points nobody
    /// thought of are marked by default. Only an emoji's own presentation
    /// selector and the joiners inside an emoji sequence pass, since those
    /// draw as part of the visible emoji.
    private static func marker(for scalar: Unicode.Scalar, emojiPart: Bool) -> String? {
        let properties = scalar.properties
        switch scalar.value {
        case 0x20: return nil
        case 0x09: return "⇥"
        case 0x00 ... 0x1F: return String(Unicode.Scalar(0x2400 + scalar.value)!) // ␀…␟, e.g. ␛
        case 0x7F: return "␡"
        case 0xFE0E ... 0xFE0F, 0x200D:
            if emojiPart { return nil }
        // Letters and symbols that draw as blanks.
        case 0x115F, 0x1160, 0x2800, 0x3164, 0xFFA0:
            return code(scalar)
        default:
            break
        }
        switch properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned,
             .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return code(scalar)
        default:
            break
        }
        if properties.isDefaultIgnorableCodePoint || properties.isBidiControl
            || properties.isNoncharacterCodePoint {
            return code(scalar)
        }
        return nil
    }

    private static func isPictographic(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return scalar.value > 0x7F && scalar.properties.isEmoji
    }

    private static func code(_ scalar: Unicode.Scalar) -> String {
        "⟨U+\(String(scalar.value, radix: 16, uppercase: true))⟩"
    }
}
