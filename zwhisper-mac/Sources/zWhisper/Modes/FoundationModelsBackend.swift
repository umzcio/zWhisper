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
                    let session = LanguageModelSession(instructions: mode.instructions)
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
    /// §6 pipeline: raw transcript + optional captured context (Super modes).
    static func build(raw: String, mode: Mode, context: CapturedContext?) -> String {
        var parts: [String] = []
        if let context {
            if mode.readsSelectedText, let selected = context.selectedText, !selected.isEmpty {
                parts.append("Context — selected text in \(context.frontmostApp):\n\(selected)")
            }
            if mode.readsClipboard, let clipboard = context.clipboard, !clipboard.isEmpty {
                parts.append("Context — clipboard:\n\(clipboard)")
            }
        }
        parts.append(raw)
        return parts.joined(separator: "\n\n")
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
