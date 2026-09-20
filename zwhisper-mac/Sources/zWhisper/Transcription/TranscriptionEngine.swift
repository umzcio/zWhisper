import AVFAudio
import Foundation
import WhisperKit

/// Architecture §3.3: final transcript with segment-level timings
/// (word-level is the known WhisperKit gap, architecture §10.5).
struct Transcript: Equatable, Sendable {
    let text: String
    let segments: [TranscriptSegment]
}

enum TranscriptionError: Error {
    case modelNotLoaded
}

/// Architecture §3.3 contract.
protocol TranscriptionEngineProtocol: Sendable {
    /// Teleprompter text during recording (§3.1, §4.2).
    var partials: AsyncStream<String> { get }
    /// Downloads (first launch) and loads the pinned default model.
    func load(progress: @escaping @Sendable (Double) -> Void) async throws
    /// Switches the active model to an already-downloaded variant (§6.4 Set Active).
    func loadModel(at folder: URL) async throws
    /// Vocabulary words (§6.5) injected via prompt tokens on every pass.
    func setVocabulary(_ words: [String]) async
    /// §6.6 Language: nil = auto-detect; translate-to-English maps to Whisper's translate task.
    func setLanguage(_ code: String?, translateToEnglish: Bool) async
    /// Voiced 16kHz buffers from the audio engine, feeding the streaming window (§5).
    func feed(_ buffer: AVAudioPCMBuffer) async
    /// Final pass over the full-session buffer on stop (§4, ≤900ms budget).
    func transcribeFinal(_ audio: AVAudioPCMBuffer) async throws -> Transcript
}

/// WhisperKit wrapper (architecture §3.3). Streaming follows the WhisperAX
/// pattern: a rolling window (capped at Whisper's 30s context — the §6.6
/// default 30s active-duration cap keeps full coverage) is re-transcribed
/// roughly every second of new voiced audio, and the hypothesis is published
/// as the partial. One pass runs at a time; a slow pass drops its tick.
actor TranscriptionEngine: TranscriptionEngineProtocol {
    nonisolated let partials: AsyncStream<String>
    private nonisolated let partialContinuation: AsyncStream<String>.Continuation

    private var whisperKit: WhisperKit?
    private var window: [Float] = []
    private var samplesSinceLastPass = 0
    private var partialTask: Task<Void, Never>?
    private var vocabularyWords: [String] = []
    private var promptTokens: [Int]?
    private var language: String?
    private var translateToEnglish = false

    init() {
        var continuation: AsyncStream<String>.Continuation!
        partials = AsyncStream { continuation = $0 }
        partialContinuation = continuation
    }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        let folder = try await ModelDownloadManager().ensureDefaultModel(progress: progress)
        try await loadModel(at: folder)
    }

    func loadModel(at folder: URL) async throws {
        let config = WhisperKitConfig(modelToken: "", modelFolder: folder.path(percentEncoded: false), prewarm: true)
        whisperKit = try await WhisperKit(config)
        rebuildPromptTokens()
    }

    func setLanguage(_ code: String?, translateToEnglish: Bool) {
        language = code
        self.translateToEnglish = translateToEnglish
    }

    func setVocabulary(_ words: [String]) {
        vocabularyWords = words
        rebuildPromptTokens()
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        window.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: count))
        // Whisper's context is 30s of 16kHz audio.
        if window.count > 480_000 {
            window.removeFirst(window.count - 480_000)
        }
        samplesSinceLastPass += count
        // Partial cadence target per §7: ≤180ms/word feel → pass per ~1s of voiced audio.
        if samplesSinceLastPass >= 16_000, partialTask == nil, whisperKit != nil {
            samplesSinceLastPass = 0
            partialTask = Task { await self.runPartialPass() }
        }
    }

    func transcribeFinal(_ audio: AVAudioPCMBuffer) async throws -> Transcript {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        let count = Int(audio.frameLength)
        let samples: [Float] = count > 0
            ? Array(UnsafeBufferPointer(start: audio.floatChannelData![0], count: count))
            : []
        let options = DecodingOptions(
            task: translateToEnglish ? .translate : .transcribe,
            language: language,
            withoutTimestamps: false,
            wordTimestamps: false,
            promptTokens: promptTokens
        )
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        window.removeAll()
        samplesSinceLastPass = 0
        let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = results.flatMap(\.segments).map {
            // Segment text can carry raw special-token markup; strip it (§6.3 transcript).
            let cleaned = $0.text
                .replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return TranscriptSegment(text: cleaned, start: TimeInterval($0.start), end: TimeInterval($0.end))
        }
        return Transcript(text: text, segments: segments)
    }

    private func runPartialPass() async {
        defer { partialTask = nil }
        guard let whisperKit, window.count > 8_000 else { return }
        do {
            let options = DecodingOptions(
                task: translateToEnglish ? .translate : .transcribe,
                language: language,
                withoutTimestamps: true,
                promptTokens: promptTokens
            )
            let results = try await whisperKit.transcribe(audioArray: window, decodeOptions: options)
            let text = results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                partialContinuation.yield(text)
            }
        } catch {
            // A dropped partial tick is invisible — the next window supersedes it.
        }
    }

    /// §6.5 gap closure: vocabulary feeds the teleprompter via prompt tokens.
    private func rebuildPromptTokens() {
        guard let tokenizer = whisperKit?.tokenizer, !vocabularyWords.isEmpty else {
            promptTokens = nil
            return
        }
        promptTokens = tokenizer.encode(text: " " + vocabularyWords.joined(separator: ", "))
    }
}
