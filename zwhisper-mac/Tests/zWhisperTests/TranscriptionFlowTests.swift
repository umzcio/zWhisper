import AVFAudio
import Foundation
import Testing
@testable import zWhisper

/// Protocol-fronted mock (architecture §3): scripted partials + final transcript.
actor MockTranscriptionEngine: TranscriptionEngineProtocol {
    nonisolated let partials: AsyncStream<String>
    private nonisolated let partialContinuation: AsyncStream<String>.Continuation

    private(set) var loadCalls = 0
    private(set) var vocabulary: [String] = []
    private(set) var fedBuffers = 0
    /// Artificial delay before the final transcript returns (transcribing-phase tests).
    var finalDelay: Duration = .zero
    var finalResult = Transcript(text: "the quick brown fox", segments: [
        TranscriptSegment(text: " the quick brown fox", start: 0, end: 1.8),
    ])

    init() {
        var continuation: AsyncStream<String>.Continuation!
        partials = AsyncStream { continuation = $0 }
        partialContinuation = continuation
    }

    func yieldPartial(_ text: String) {
        partialContinuation.yield(text)
    }

    func setFinalDelay(_ delay: Duration) {
        finalDelay = delay
    }

    func setFinalResult(_ result: Transcript) {
        finalResult = result
    }

    func load(progress: @Sendable (Double) -> Void) async throws {
        loadCalls += 1
        progress(1)
    }

    func loadModel(at folder: URL) async throws {
        loadCalls += 1
    }

    func setLanguage(_ code: String?, translateToEnglish: Bool) {}

    func setVocabulary(_ words: [String]) {
        vocabulary = words
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        fedBuffers += 1
    }

    func transcribeFinal(_ audio: AVAudioPCMBuffer) async throws -> Transcript {
        if finalDelay > .zero {
            try? await Task.sleep(for: finalDelay)
        }
        return finalResult
    }
}

@Suite("AppState transcription flow (M3)")
@MainActor
struct TranscriptionFlowTests {
    private func makeState() async -> (AppState, MockAudioCaptureEngine, MockTranscriptionEngine) {
        let audio = MockAudioCaptureEngine()
        let transcription = MockTranscriptionEngine()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        let state = AppState(
            audio: audio,
            transcription: transcription,
            paste: MockPasteController(),
            persistence: PersistenceStore(directory: dir),
            requestRecordPermission: { true }
        )
        return (state, audio, transcription)
    }

    private func makeBuffer(frames: Int = 1600) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }

    @Test("prepareTranscription downloads, loads, then applies vocabulary")
    func prepare() async throws {
        let (state, _, transcription) = await makeState()
        #expect(state.modelStatus == .notStarted)
        await state.prepareTranscription()
        #expect(state.modelStatus == .ready)
        #expect(await transcription.loadCalls == 1)
    }

    @Test("dictation is gated on the speech model being ready")
    func modelGate() async throws {
        let (state, audio, _) = await makeState()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.phase == .idle)
        #expect(await audio.startCalls == 0)
        await state.prepareTranscription()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        guard case .recording = state.phase else {
            Issue.record("expected recording after model ready")
            return
        }
    }

    @Test("voiced buffers reach the transcription engine; partials update the teleprompter")
    func partials() async throws {
        let (state, audio, transcription) = await makeState()
        await state.prepareTranscription()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))

        await audio.pushBuffer(makeBuffer())
        try await Task.sleep(for: .milliseconds(100))
        #expect(await transcription.fedBuffers == 1)

        await transcription.yieldPartial("the quick brown")
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.partialText == "the quick brown")
    }

    @Test("stop → transcribing → final transcript shown, phase pasted (M4 pipeline)")
    func stopFlow() async throws {
        let (state, _, transcription) = await makeState()
        await state.prepareTranscription()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        state.stopDictation()
        try await Task.sleep(for: .milliseconds(300))
        guard case .pasted = state.phase else {
            Issue.record("expected pasted phase, got \(state.phase)")
            return
        }
        #expect(state.transcriptText == "the quick brown fox")
        #expect(state.partialText == "")
        #expect(state.lastTranscript?.segments.count == 1)
    }

    @Test("Esc during transcribing cancels the pass and clears the teleprompter")
    func cancelDuringTranscribing() async throws {
        let (state, _, transcription) = await makeState()
        await transcription.setFinalDelay(.seconds(2))
        await state.prepareTranscription()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        state.stopDictation()
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.phase == .transcribing)

        state.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.phase == .idle)
        #expect(state.partialText == "")
        try await Task.sleep(for: .milliseconds(500))
        #expect(!state.isPopoverOpen)
    }

    @Test("vocabulary words load from disk and reach the engine (§6.5)")
    func vocabulary() async throws {
        let (state, _, transcription) = await makeState()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        let store = PersistenceStore(directory: dir)
        let vocab = VocabularyStore(
            customWords: [Word(id: UUID(), text: "Aysima", useCount: 0, lastUsedAt: nil)],
            replacements: []
        )
        try await store.save(vocab, to: "vocabulary.json")

        let stateWithVocab = AppState(
            audio: MockAudioCaptureEngine(),
            transcription: transcription,
            persistence: store,
            requestRecordPermission: { true }
        )
        await stateWithVocab.loadVocabulary()
        #expect(await transcription.vocabulary == ["Aysima"])
        _ = state
    }
}
