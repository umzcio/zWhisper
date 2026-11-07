import FluidAudio
import Foundation

/// Parakeet TDT 0.6B v3 (Ultra post-training) via FluidAudio. A batch model,
/// fast enough (~100x real time on the Neural Engine) to re-run the session's
/// voiced audio once per second for the live preview. Custom vocabulary goes
/// through FluidAudio's CTC keyword spotter, which rescores the final pass.
actor ParakeetEngine: SpeechBackend {
    private let asr: AsrManager
    private let onPartial: @Sendable (String) -> Void
    private var window: [Float] = []
    private var samplesSinceLastPass = 0
    private var partialTask: Task<Void, Never>?
    private var language: Language?
    private var vocabularyWords: [String] = []
    private var boosting: VocabularyBoostingSession?
    private var ctcModels: CtcModels?

    /// FluidAudio rejects audio under one second; shorter takes are padded with silence.
    private static let minimumSamples = 16_000
    /// The preview re-runs at most the last 30s, like Whisper's window.
    private static let previewWindowSamples = 480_000

    static func load(folder: URL, onPartial: @escaping @Sendable (String) -> Void) async throws -> ParakeetEngine {
        let models = try await AsrModels.load(from: folder, version: FluidModelStore.parakeetVersion)
        // FluidAudio's load may tidy or refetch the cache: re-check after it.
        try ModelPins.verifyInstalled(LocalModelFamily.parakeetID)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        return ParakeetEngine(asr: asr, onPartial: onPartial)
    }

    private init(asr: AsrManager, onPartial: @escaping @Sendable (String) -> Void) {
        self.asr = asr
        self.onPartial = onPartial
    }

    func setLanguage(_ code: String?, translateToEnglish: Bool) {
        // Script filtering for the 25 supported languages; anything else is auto.
        language = code.flatMap(Language.init(rawValue:))
    }

    func setVocabulary(_ words: [String]) async {
        vocabularyWords = words
        guard !words.isEmpty else {
            boosting = nil
            return
        }
        do {
            if ctcModels == nil {
                let loaded = try await CtcModels.load(from: FluidModelStore.ctcFolder, variant: .ctc110m)
                // FluidAudio's load can tidy or refetch the cache (one-time
                // adoption of pre-pin downloads), so re-check its files after:
                // the vocabulary model is only used if it still matches its pins.
                try ModelPins.verifyInstalled(LocalModelFamily.parakeetID)
                ctcModels = loaded
            }
            guard let ctcModels, vocabularyWords == words else { return }
            let context = CustomVocabularyContext(terms: words.map { CustomVocabularyTerm(text: $0) })
            // FluidAudio's dictation setting (#967): a wrong replacement costs
            // more than a miss, so require acoustic evidence and close spelling.
            let session = try await VocabularyBoostingSession(
                vocabulary: context,
                ctcModels: ctcModels,
                thresholds: .init(cbw: 0, minSimilarity: 0.7)
            )
            if vocabularyWords == words { boosting = session }
        } catch {
            boosting = nil
        }
    }

    func feed(_ samples: [Float]) {
        window.append(contentsOf: samples)
        if window.count > Self.previewWindowSamples {
            window.removeFirst(window.count - Self.previewWindowSamples)
        }
        samplesSinceLastPass += samples.count
        if samplesSinceLastPass >= 16_000, partialTask == nil {
            samplesSinceLastPass = 0
            partialTask = Task { await self.runPartialPass() }
        }
    }

    func transcribeFinal(_ samples: [Float]) async throws -> Transcript {
        await stopPreview()
        guard !samples.isEmpty else { return Transcript(text: "", segments: []) }
        let audio = Self.padded(samples)
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result = try await asr.transcribe(audio, decoderState: &state, language: language)
        var text = result.text
        if let boosting, let timings = result.tokenTimings,
           let rescored = await boosting.rescore(text: text, tokenTimings: timings, audioSamples: audio),
           rescored.wasModified
        {
            text = rescored.text
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = TimeInterval(samples.count) / 16_000
        return Transcript(text: text, segments: text.isEmpty ? [] : [TranscriptSegment(text: text, start: 0, end: duration)])
    }

    func resetStream() async {
        await stopPreview()
    }

    private func stopPreview() async {
        let task = partialTask
        task?.cancel()
        await task?.value
        window.removeAll()
        samplesSinceLastPass = 0
    }

    private func runPartialPass() async {
        defer { partialTask = nil }
        guard window.count > 8_000 else { return }
        let audio = Self.padded(window)
        do {
            var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
            let result = try await asr.transcribe(audio, decoderState: &state, language: language)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, !Task.isCancelled {
                onPartial(text)
            }
        } catch {
            // A dropped partial tick is invisible; the next one supersedes it.
        }
    }

    private static func padded(_ samples: [Float]) -> [Float] {
        samples.count >= minimumSamples
            ? samples
            : samples + [Float](repeating: 0, count: minimumSamples - samples.count)
    }
}

/// Nemotron 3.5 ASR Streaming 0.6B (multilingual, 1120 ms chunks) via
/// FluidAudio. The preview is true streaming: each voiced buffer is decoded
/// once, in order, by a cache-aware encoder. The stream only sees voiced
/// audio, so the final pass re-decodes the full session from a clean state.
/// Custom vocabulary biases the decoder directly (shallow fusion).
actor NemotronEngine: SpeechBackend {
    private let manager: StreamingNemotronMultilingualAsrManager
    private let onPartial: @Sendable (String) -> Void
    private var pending: [Float] = []
    private var drainTask: Task<Void, Never>?
    /// False while a final pass owns the decoder; stray buffers are dropped.
    private var acceptsStream = true
    /// The stream since the last reset hasn't been primed with lead-in yet.
    private var streamIsFresh = true
    private var lastPartial = ""

    /// The cache-aware encoder drops the first word when speech starts at
    /// sample 0 (measured: "Then the fox…" → "The fox…"); 300 ms of silence
    /// ahead of each decode fixes it.
    static let leadIn = [Float](repeating: 0, count: 4_800)

    static func load(folder: URL, onPartial: @escaping @Sendable (String) -> Void) async throws -> NemotronEngine {
        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: folder)
        return NemotronEngine(manager: manager, onPartial: onPartial)
    }

    private init(manager: StreamingNemotronMultilingualAsrManager, onPartial: @escaping @Sendable (String) -> Void) {
        self.manager = manager
        self.onPartial = onPartial
    }

    func setLanguage(_ code: String?, translateToEnglish: Bool) async {
        await manager.setLanguage(Self.promptLanguage(for: code))
    }

    func setVocabulary(_ words: [String]) async {
        await manager.setCustomVocabulary(words.map { CustomVocabularyTerm(text: $0) })
    }

    func feed(_ samples: [Float]) {
        guard acceptsStream else { return }
        if streamIsFresh {
            streamIsFresh = false
            pending.append(contentsOf: Self.leadIn)
        }
        pending.append(contentsOf: samples)
        if drainTask == nil {
            drainTask = Task { await self.drain() }
        }
    }

    func transcribeFinal(_ samples: [Float]) async throws -> Transcript {
        acceptsStream = false
        defer { acceptsStream = true }
        await stopStream()
        guard !samples.isEmpty else { return Transcript(text: "", segments: []) }
        do {
            _ = try await manager.process(samples: Self.leadIn + samples)
            let raw = try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
            let text = Self.closingSentence(raw, language: await manager.detectedLanguage())
            await manager.reset()
            let duration = TimeInterval(samples.count) / 16_000
            return Transcript(text: text, segments: text.isEmpty ? [] : [TranscriptSegment(text: text, start: 0, end: duration)])
        } catch {
            await manager.reset()
            throw error
        }
    }

    func resetStream() async {
        await stopStream()
    }

    /// Feeds pending audio in arrival order; one drain runs at a time, so
    /// chunks reach the stateful encoder sequentially.
    private func drain() async {
        while !pending.isEmpty, !Task.isCancelled {
            let batch = pending
            pending.removeAll()
            do {
                _ = try await manager.process(samples: batch)
            } catch {
                break
            }
            let text = await manager.getPartialTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
            // A chunk is 1.12 s; buffers that don't complete one change nothing.
            if !text.isEmpty, text != lastPartial, !Task.isCancelled {
                lastPartial = text
                onPartial(text)
            }
        }
        drainTask = nil
    }

    private func stopStream() async {
        pending.removeAll()
        let task = drainTask
        task?.cancel()
        await task?.value
        drainTask = nil
        await manager.reset()
        streamIsFresh = true
        lastPartial = ""
    }

    /// The last chunk has no right context, so the model rarely closes the
    /// final sentence; Whisper and Parakeet always do, and SmartJoin's
    /// capitalization of the next dictation depends on it.
    static func closingSentence(_ text: String, language: String?) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        let isCJK = language.map { $0.hasPrefix("zh") || $0.hasPrefix("ja") } ?? false
        return text + (isCJK ? "。" : ".")
    }

    /// zWhisper's language codes → the model's prompt dictionary. Japanese and
    /// Chinese have only region-qualified prompts; nil is auto-detect.
    static func promptLanguage(for code: String?) -> String {
        switch code {
        case nil, "auto": "auto"
        case "ja": "ja-JP"
        case "zh": "zh-CN"
        case let code?: code
        }
    }
}
