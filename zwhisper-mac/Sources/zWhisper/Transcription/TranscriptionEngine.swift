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
    /// Switches the active model to an already-downloaded catalog row (§6.4 Set Active).
    func loadModel(_ id: String) async throws
    /// Vocabulary words (§6.5) biasing every pass.
    func setVocabulary(_ words: [String]) async
    /// §6.6 Language: nil = auto-detect; translate-to-English maps to Whisper's translate task.
    func setLanguage(_ code: String?, translateToEnglish: Bool) async
    /// Voiced 16kHz buffers from the audio engine, feeding the live preview (§5).
    func feed(_ buffer: AVAudioPCMBuffer) async
    /// Final pass over the full-session buffer on stop (§4, ≤900ms budget).
    func transcribeFinal(_ audio: AVAudioPCMBuffer) async throws -> Transcript
    /// Drops the live-preview state, so one session's audio can't leak into
    /// the next session's preview (cancelled sessions, cloud final passes).
    func resetStream() async
}

/// One on-device engine (Whisper, Parakeet, Nemotron). Audio is 16 kHz mono.
/// Partials go to the callback the backend was created with.
protocol SpeechBackend: Actor {
    func setVocabulary(_ words: [String]) async
    func setLanguage(_ code: String?, translateToEnglish: Bool) async
    func feed(_ samples: [Float]) async
    func transcribeFinal(_ samples: [Float]) async throws -> Transcript
    func resetStream() async
}

/// Routes the §3.3 contract to the active catalog row's engine, and replays
/// the language and vocabulary onto each newly loaded one.
actor TranscriptionEngine: TranscriptionEngineProtocol {
    nonisolated let partials: AsyncStream<String>
    private nonisolated let partialContinuation: AsyncStream<String>.Continuation

    private var backend: (any SpeechBackend)?
    private var vocabularyWords: [String] = []
    private var language: String?
    private var translateToEnglish = false

    init() {
        var continuation: AsyncStream<String>.Continuation!
        partials = AsyncStream { continuation = $0 }
        partialContinuation = continuation
    }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await ModelDownloadManager().ensureDefaultModel(progress: progress)
        try await loadModel(ModelDownloadManager.defaultModelName)
    }

    func loadModel(_ id: String) async throws {
        // Models downloaded by an older build are hashed once against the
        // pins before their first load; a mismatch deletes them (ModelPins).
        try ModelPins.verifyInstalled(id)
        let folder = ModelDownloadManager.modelFolder(forVariant: id)
        let onPartial: @Sendable (String) -> Void = { [partialContinuation] in partialContinuation.yield($0) }
        let next: any SpeechBackend = switch LocalModelFamily(id: id) {
        case .whisper: try await WhisperEngine.load(folder: folder, onPartial: onPartial)
        case .parakeet: try await ParakeetEngine.load(folder: folder, onPartial: onPartial)
        case .nemotron: try await NemotronEngine.load(folder: folder, onPartial: onPartial)
        }
        await next.setLanguage(language, translateToEnglish: translateToEnglish)
        await next.setVocabulary(vocabularyWords)
        backend = next
    }

    func setLanguage(_ code: String?, translateToEnglish: Bool) async {
        language = code
        self.translateToEnglish = translateToEnglish
        await backend?.setLanguage(code, translateToEnglish: translateToEnglish)
    }

    func setVocabulary(_ words: [String]) async {
        vocabularyWords = words
        await backend?.setVocabulary(words)
    }

    func feed(_ buffer: AVAudioPCMBuffer) async {
        let samples = Self.samples(of: buffer)
        guard !samples.isEmpty else { return }
        await backend?.feed(samples)
    }

    func transcribeFinal(_ audio: AVAudioPCMBuffer) async throws -> Transcript {
        guard let backend else { throw TranscriptionError.modelNotLoaded }
        return try await backend.transcribeFinal(Self.samples(of: audio))
    }

    func resetStream() async {
        await backend?.resetStream()
    }

    private static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        let count = Int(buffer.frameLength)
        guard count > 0, let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: count))
    }
}

/// WhisperKit backend (architecture §3.3). Streaming follows the WhisperAX
/// pattern: a rolling window (capped at Whisper's 30s context — the §6.6
/// default 30s active-duration cap keeps full coverage) is re-transcribed
/// roughly every second of new voiced audio, and the hypothesis is published
/// as the partial. One pass runs at a time; a slow pass drops its tick.
actor WhisperEngine: SpeechBackend {
    private let whisperKit: WhisperKit
    private let onPartial: @Sendable (String) -> Void
    private var window: [Float] = []
    private var samplesSinceLastPass = 0
    private var partialTask: Task<Void, Never>?
    private var vocabularyWords: [String] = []
    private var promptTokens: [Int]?
    private var language: String?
    private var translateToEnglish = false

    static func load(folder: URL, onPartial: @escaping @Sendable (String) -> Void) async throws -> WhisperEngine {
        let config = WhisperKitConfig(modelToken: "", modelFolder: folder.path(percentEncoded: false), prewarm: true)
        return WhisperEngine(whisperKit: try await WhisperKit(config), onPartial: onPartial)
    }

    private init(whisperKit: WhisperKit, onPartial: @escaping @Sendable (String) -> Void) {
        self.whisperKit = whisperKit
        self.onPartial = onPartial
    }

    func setLanguage(_ code: String?, translateToEnglish: Bool) {
        language = code
        self.translateToEnglish = translateToEnglish
    }

    func setVocabulary(_ words: [String]) {
        vocabularyWords = words
        rebuildPromptTokens()
    }

    func feed(_ samples: [Float]) {
        window.append(contentsOf: samples)
        // Whisper's context is 30s of 16kHz audio.
        if window.count > 480_000 {
            window.removeFirst(window.count - 480_000)
        }
        samplesSinceLastPass += samples.count
        // Partial cadence target per §7: ≤180ms/word feel → pass per ~1s of voiced audio.
        if samplesSinceLastPass >= 16_000, partialTask == nil {
            samplesSinceLastPass = 0
            partialTask = Task { await self.runPartialPass() }
        }
    }

    func transcribeFinal(_ samples: [Float]) async throws -> Transcript {
        let options = DecodingOptions(
            task: translateToEnglish ? .translate : .transcribe,
            language: language,
            withoutTimestamps: false,
            wordTimestamps: false,
            promptTokens: promptTokens
        )
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        resetStream()
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

    func resetStream() {
        window.removeAll()
        samplesSinceLastPass = 0
    }

    private func runPartialPass() async {
        defer { partialTask = nil }
        guard window.count > 8_000 else { return }
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
                onPartial(text)
            }
        } catch {
            // A dropped partial tick is invisible — the next window supersedes it.
        }
    }

    /// §6.5 gap closure: vocabulary feeds the teleprompter via prompt tokens.
    private func rebuildPromptTokens() {
        guard let tokenizer = whisperKit.tokenizer, !vocabularyWords.isEmpty else {
            promptTokens = nil
            return
        }
        promptTokens = tokenizer.encode(text: " " + vocabularyWords.joined(separator: ", "))
    }
}
