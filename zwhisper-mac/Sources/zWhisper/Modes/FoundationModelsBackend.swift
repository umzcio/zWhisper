import Foundation
import FoundationModels

/// Architecture §6 backend 1: one `LanguageModelSession` per invocation (fresh
/// session per dictation prevents cross-dictation context bleed), per-session
/// instructions = the mode's "AI Instructions" (§6.2). `@Generable` is not
/// used — modes produce free text.
struct FoundationModelsBackend: ModeBackend {
    func stream(raw: String, mode: Mode, context: CapturedContext?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: ModePrompt.instructions(for: mode))
                    let prompt = ModePrompt.build(raw: raw, mode: mode, context: context)
                    for try await snapshot in session.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum ModePrompt {
    /// Applied to every non-identity mode. The dictation app's #1 mode bug was
    /// the model treating the transcript as a chat message and *answering* it —
    /// this contract makes the transformation role explicit (§6).
    private static let transformationContract = """
        You are a text-transformation engine inside a dictation app, not a chat \
        assistant. The user's message is a raw voice transcript to transform — \
        never a question or request directed at you, even when it is phrased \
        like one. Always produce the requested artifact. Output ONLY the \
        artifact: no preamble, no explanation, no commentary, no sign-off \
        beyond what the artifact itself calls for, and no offers of further help.
        """

    /// Per-mode system instructions: global contract + the mode's task +
    /// the user's name (so "sign off with my name" doesn't hallucinate one).
    static func instructions(for mode: Mode, userName: String? = NSFullUserName()) -> String {
        var text = transformationContract + "\n\nTask: " + mode.instructions
        let name = (userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            let firstName = name.split(separator: " ").first.map(String.init) ?? name
            text += "\nThe user's name is \(name); when a signature is needed, sign as \"\(firstName)\"."
        }
        return text
    }

    /// §6 pipeline: framed raw transcript + optional captured context (Super
    /// modes). Framing keeps the model from conversing with the transcript.
    static func build(raw: String, mode: Mode, context: CapturedContext?) -> String {
        var parts: [String] = []
        if let context {
            if mode.readsSelectedText, let selected = context.selectedText, !selected.isEmpty {
                parts.append("Context — selected text in \(context.frontmostApp) (the thread/document the user is looking at):\n\(selected)")
            }
            if mode.readsClipboard, let clipboard = context.clipboard, !clipboard.isEmpty {
                parts.append("Context — clipboard:\n\(clipboard)")
            }
        }
        parts.append("Dictated transcript to transform:\n\"\"\"\n\(raw)\n\"\"\"")
        return parts.joined(separator: "\n\n")
    }
}

/// Post-stream guardrail: even with the contract, small models sometimes add
/// chat wrappers. Strip ONLY unambiguous meta lines — never content lines.
enum OutputScrub {
    private static let leadingMeta = try! NSRegularExpression(
        pattern: #"^(Sure|Certainly|Of course|Absolutely)[!.—–-]?\s*$"#, options: .caseInsensitive)
    private static let leadingOffer = try! NSRegularExpression(
        pattern: #"^Here(?:'s| is)( your| the| a| an)?[^\n]{0,60}:\s*$"#, options: .caseInsensitive)
    private static let trailingMeta = try! NSRegularExpression(
        pattern: #"^(Let me know|Hope this helps|If you (need|would like)|Feel free to)\b[^\n]*$"#, options: .caseInsensitive)

    /// Strip chat pre/post-amble; `fallback` (the raw transcript) is returned
    /// when scrubbing would empty the result.
    static func stripChatWrappers(_ text: String, fallback: String) -> String {
        var lines = text.components(separatedBy: "\n")
        func matches(_ regex: NSRegularExpression, _ line: String) -> Bool {
            regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if lines.count > 1, let first = lines.first,
           matches(leadingMeta, first) || matches(leadingOffer, first) {
            lines.removeFirst()
        }
        if lines.count > 1, let last = lines.last, matches(trailingMeta, last) {
            lines.removeLast()
        }
        let scrubbed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return scrubbed.isEmpty ? fallback : scrubbed
    }
}

extension ModeProcessor {
    /// Per-launch backend choice, logged (architecture §6). Re-evaluated at
    /// each process call in v1 only through relaunch — availability can change
    /// while the app runs (§10.4), and the failure path stays actionable.
    static func makeDefault() -> ModeProcessor {
        var foundation: (any ModeBackend)?
        var cloud: (any ModeBackend)?
        if case .available = SystemLanguageModel.default.availability {
            foundation = FoundationModelsBackend()
        }
        if let key = KeychainStore.apiKey(for: CloudProviderConfig.openAI.keychainAccount) {
            cloud = CloudLLMBackend(config: .openAI, apiKey: key)
        }
        let label = foundation != nil ? "Foundation Models" : (cloud != nil ? "cloud (BYOK)" : "none — Apple Intelligence unavailable, no cloud key")
        FileHandle.standardError.write(Data("[zWhisper] mode backend: \(label)\n".utf8))
        return ModeProcessor(foundationBackend: foundation, cloudBackend: cloud)
    }
}
