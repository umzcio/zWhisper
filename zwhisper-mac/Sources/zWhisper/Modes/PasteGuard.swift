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
    /// target app will see, so nothing typed can hide past a line break.
    /// Every line terminator splits (CR alone acts as Return in a terminal),
    /// and characters that are invisible or reorder text are drawn as
    /// visible markers.
    static func reviewLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A where previousWasCR:
                previousWasCR = false
                continue // CRLF is one break
            case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029:
                lines.append(String(current))
                current = String.UnicodeScalarView()
                previousWasCR = scalar.value == 0x0D
                continue
            default:
                previousWasCR = false
            }
            current.append(contentsOf: visible(scalar).unicodeScalars)
        }
        lines.append(String(current))
        return lines
    }

    private static func visible(_ scalar: Unicode.Scalar) -> String {
        switch scalar.value {
        case 0x09: return "⇥"
        case 0x00 ... 0x1F: return String(Unicode.Scalar(0x2400 + scalar.value)!) // ␀…␟, e.g. ␛
        case 0x7F: return "␡"
        case 0x80 ... 0x9F, 0x200B ... 0x200F, 0x202A ... 0x202E, 0x2060 ... 0x2069, 0xFEFF:
            return "⟨U+\(String(scalar.value, radix: 16, uppercase: true))⟩"
        default: return String(scalar)
        }
    }
}
