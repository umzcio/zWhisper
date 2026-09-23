import AVFAudio
import Foundation
import Testing
@testable import zWhisper

/// Protocol-fronted mock (architecture §3): replays the engine surface without hardware.
actor MockAudioCaptureEngine: AudioCaptureEngineProtocol {
    nonisolated let levels: AsyncStream<Float>
    nonisolated let buffers: AsyncStream<AVAudioPCMBuffer>

    private nonisolated let levelContinuation: AsyncStream<Float>.Continuation
    private nonisolated let bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var cancelCalls = 0
    private(set) var meteringActive = false
    private(set) var normalization: Bool?
    private(set) var silence: (enabled: Bool, aggressiveness: Int)?

    /// When armed, the next start() suspends until releaseStartGate() —
    /// lets tests interleave events inside the async start window.
    private var startGateArmed = false
    private var startGate: CheckedContinuation<Void, Never>?

    func armStartGate() {
        startGateArmed = true
    }

    func releaseStartGate() {
        startGate?.resume()
        startGate = nil
    }

    init() {
        var levelContinuation: AsyncStream<Float>.Continuation!
        levels = AsyncStream { levelContinuation = $0 }
        self.levelContinuation = levelContinuation
        var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        buffers = AsyncStream { bufferContinuation = $0 }
        self.bufferContinuation = bufferContinuation
    }

    func pushLevel(_ rms: Float) {
        levelContinuation.yield(rms)
    }

    func pushBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferContinuation.yield(buffer)
    }

    func setNormalizationEnabled(_ enabled: Bool) {
        normalization = enabled
    }

    func setSilenceRemoval(enabled: Bool, aggressiveness: Int) {
        silence = (enabled, aggressiveness)
    }

    func start() async throws {
        startCalls += 1
        if startGateArmed {
            startGateArmed = false
            await withCheckedContinuation { startGate = $0 }
        }
    }

    func stop() -> AVAudioPCMBuffer {
        stopCalls += 1
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        return buffer
    }

    var sessionAudioRelativePath: String? {
        stopCalls > 0 ? "audio/mock-session.m4a" : "audio/mock-recording.m4a"
    }

    func cancel() {
        cancelCalls += 1
    }

    func startMetering() async throws {
        meteringActive = true
    }

    func stopMetering() {
        meteringActive = false
    }

    nonisolated(unsafe) var inputAvailable = true

    nonisolated func inputIsAvailable() -> Bool {
        inputAvailable
    }

    private(set) var inputDeviceUID: String??

    func setInputDevice(uid: String?) {
        inputDeviceUID = uid
    }
}

@Suite("AppState dictation (M2)")
@MainActor
struct AppStateDictationTests {
    private func makeState(
        permission: @escaping @Sendable () async -> Bool = { true }
    ) async -> (AppState, MockAudioCaptureEngine) {
        let mock = MockAudioCaptureEngine()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        let state = AppState(
            audio: mock,
            transcription: MockTranscriptionEngine(),
            paste: MockPasteController(),
            persistence: PersistenceStore(directory: dir),
            requestRecordPermission: permission
        )
        await state.prepareTranscription()
        return (state, mock)
    }

    @Test("startDictation grants → recording, engine started, popover summoned")
    func start() async throws {
        let (state, mock) = await makeState()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        guard case .recording = state.phase else {
            Issue.record("expected recording phase, got \(state.phase)")
            return
        }
        #expect(await mock.startCalls == 1)
        #expect(state.isPopoverOpen)
        #expect(state.waveform.state == .live)
    }

    @Test("permission denied → stays idle, popover shows grant state (§8)")
    func permissionDenied() async throws {
        let (state, mock) = await makeState(permission: { false })
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.phase == .idle)
        #expect(state.micDenied)
        #expect(state.isPopoverOpen)
        #expect(await mock.startCalls == 0)
    }

    @Test("⌥⇧Space toggle: idle → recording → idle, engine stopped")
    func toggle() async throws {
        let (state, mock) = await makeState()
        state.toggleDictation()
        try await Task.sleep(for: .milliseconds(100))
        guard case .recording = state.phase else {
            Issue.record("expected recording")
            return
        }
        state.toggleDictation()
        try await Task.sleep(for: .milliseconds(300))
        // M4: stop continues into the paste pipeline instead of returning to idle.
        guard case .pasted = state.phase else {
            Issue.record("expected pasted phase, got \(state.phase)")
            return
        }
        #expect(await mock.stopCalls == 1)
        #expect(state.waveform.state == .settling)
    }

    @Test("Esc cancel during recording discards the session (no stop, no file)")
    func cancelDiscards() async throws {
        let (state, mock) = await makeState()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        state.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.phase == .idle)
        #expect(await mock.cancelCalls == 1)
        #expect(await mock.stopCalls == 0)
        #expect(state.waveform.state == .idle)
        try await Task.sleep(for: .milliseconds(500))
        #expect(!state.isPopoverOpen)
    }

    @Test("active-duration cap auto-stops the recording (§6.6 backstop)")
    func activeDurationCap() async throws {
        let (state, mock) = await makeState()
        state.settings.activeDuration = 0.3
        state.startDictation()
        // Watchdog ticks every 500ms; the pipeline then runs and the 700ms
        // auto-dismiss may already have returned the phase to idle — assert
        // the side effects, not the transient phase.
        try await Task.sleep(for: .milliseconds(1400))
        #expect(await mock.stopCalls == 1)
        #expect(state.history.count == 1)
    }

    @Test("voice then trailing silence ends the dictation (pause-friendly)")
    func trailingSilenceStop() async throws {
        let (state, mock) = await makeState()
        state.trailingSilence = 1.5
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        await mock.pushLevel(0.5) // voice
        try await Task.sleep(for: .milliseconds(100))
        // 1.5s of quiet + up to one 500ms watchdog tick + pipeline time.
        try await Task.sleep(for: .milliseconds(2400))
        #expect(await mock.stopCalls == 1)
        #expect(state.history.count == 1)
    }

    @Test("no voice at all → silence-stop never fires (wall clock only)")
    func noVoiceNoSilenceStop() async throws {
        let (state, _) = await makeState()
        state.trailingSilence = 0.5
        state.settings.activeDuration = nil
        state.startDictation()
        try await Task.sleep(for: .milliseconds(1500))
        guard case .recording = state.phase else {
            Issue.record("expected recording to continue with no voice heard, got \(state.phase)")
            return
        }
        state.cancel()
    }

    @Test("held PTT ignores trailing silence; release is the stop")
    func pttIgnoresTrailingSilence() async throws {
        let (state, mock) = await makeState()
        state.trailingSilence = 0.5
        state.settings.activeDuration = nil
        state.startPushToTalk()
        try await Task.sleep(for: .milliseconds(100))
        await mock.pushLevel(0.5)
        try await Task.sleep(for: .milliseconds(1200))
        guard case .recording = state.phase else {
            Issue.record("expected recording to continue while PTT held, got \(state.phase)")
            return
        }
        state.stopPushToTalk()
        try await Task.sleep(for: .milliseconds(400))
        guard case .pasted = state.phase else {
            Issue.record("expected pasted after PTT release, got \(state.phase)")
            return
        }
    }

    @Test("tap RMS forwards to currentLevel as a normalized 0…1 value")
    func levelForwarding() async throws {
        let (state, mock) = await makeState()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        await mock.pushLevel(0.25) // ≈ −12dB → top of the window
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.currentLevel > 0.9)
        await mock.pushLevel(0.000_01) // silence
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.currentLevel < 0.05)
    }

    @Test("settings changes propagate to the engine and persist debounced")
    func settingsPropagation() async throws {
        let (state, mock) = await makeState()
        state.settings.dynamicNormalization = false
        state.settings.silenceAggressiveness = 80
        state.settings.inputDeviceUID = "test-device-uid"
        state.settingsDidChange()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await mock.normalization == false)
        #expect(await mock.silence?.aggressiveness == 80)
        #expect(await mock.inputDeviceUID == "test-device-uid")
    }

    @Test("metering runs levels-only while the Sound pane is visible")
    func metering() async throws {
        let (state, mock) = await makeState()
        state.startMetering()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await mock.meteringActive)
        await mock.pushLevel(0.25)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.currentLevel > 0.9)
        state.stopMetering()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await !mock.meteringActive)
        #expect(state.currentLevel == 0)
    }

    @Test("no input hardware → actionable hint, no permission request, no engine start")
    func noInputDevice() async throws {
        let (state, mock) = await makeState()
        mock.inputAvailable = false
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.phase == .idle)
        #expect(state.audioFailure == "No microphone found — connect one and try again.")
        #expect(!state.micDenied)
        #expect(await mock.startCalls == 0)
        #expect(state.isPopoverOpen)
        // Hardware appears (user connects a mic) → the next attempt proceeds.
        mock.inputAvailable = true
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await mock.startCalls == 1)
        guard case .recording = state.phase else {
            Issue.record("expected recording after mic connected, got \(state.phase)")
            return
        }
        #expect(state.audioFailure == nil)
    }

    @Test("double stop inside the stop window transcribes once (race regression)")
    func doubleStop() async throws {
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
        await state.prepareTranscription()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        guard case .recording = state.phase else {
            Issue.record("expected recording, got \(state.phase)")
            return
        }
        // Two stop triggers in immediate succession (PTT release + toggle).
        state.stopDictation()
        state.stopDictation()
        try await Task.sleep(for: .milliseconds(400))
        #expect(await transcription.finalCalls == 1)
        #expect(await audio.stopCalls == 1)
        #expect(state.history.count == 1)
    }

    @Test("quick PTT tap (release before engine start completes) ends idle")
    func quickPTTTap() async throws {
        let (state, mock) = await makeState()
        await mock.armStartGate()
        state.startPushToTalk()
        for _ in 0 ..< 50 {
            if await mock.startCalls == 1 { break } // start is parked in the gate
            try await Task.sleep(for: .milliseconds(10))
        }
        state.stopPushToTalk()
        await mock.releaseStartGate()
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.phase == .idle)
        #expect(!state.holdToTalkActive)
        #expect(await mock.cancelCalls >= 1)
        #expect(state.history.isEmpty)
    }

    @Test("double start inside the start window starts the engine once")
    func doubleStart() async throws {
        let (state, mock) = await makeState()
        await mock.armStartGate()
        state.startDictation()
        state.startDictation()
        // Wait until the first start is actually parked in the gate before
        // releasing (startCalls increments ahead of the suspension).
        for _ in 0 ..< 50 {
            if await mock.startCalls == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await mock.releaseStartGate()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await mock.startCalls == 1)
        guard case .recording = state.phase else {
            Issue.record("expected recording, got \(state.phase)")
            return
        }
    }
}

@Suite("WaveformModel (§3.2)")
@MainActor
struct WaveformModelTests {
    @Test("idle bars follow the static formula, min height 2")
    func idle() {
        let model = WaveformModel()
        let heights = model.update(barCount: 48, maxHeight: 80, level: 0, now: .now)
        #expect(heights.count == 48)
        for height in heights {
            #expect(height >= 2)
            #expect(height <= 80)
        }
    }

    @Test("live bars lerp toward the RMS-driven target")
    func live() {
        let model = WaveformModel()
        model.beginLive()
        var heights = model.update(barCount: 48, maxHeight: 80, level: 0, now: .now)
        let centerBefore = heights[24]
        for _ in 0 ..< 30 {
            heights = model.update(barCount: 48, maxHeight: 80, level: 1, now: .now)
        }
        // Center bar reads the newest sample → converges near max (2 + 1·(80−6) = 76).
        #expect(heights[24] > 70)
        #expect(heights[24] > centerBefore)
    }

    @Test("settle collapses bars center-out and returns to idle")
    func settle() {
        let model = WaveformModel()
        model.beginLive()
        let start = Date.now
        for _ in 0 ..< 30 {
            _ = model.update(barCount: 48, maxHeight: 80, level: 1, now: start)
        }
        model.beginSettle(now: start, barCount: 48)
        #expect(model.state == .settling)

        // Frames at t+0.15s: the center slot (delay ≈6ms) is collapsing while
        // the edge slot (delay 0.3s) still holds — the center-out stagger.
        var heights = model.update(barCount: 48, maxHeight: 80, level: 0, now: start.addingTimeInterval(0.15))
        for _ in 0 ..< 5 {
            heights = model.update(barCount: 48, maxHeight: 80, level: 0, now: start.addingTimeInterval(0.15))
        }
        #expect(heights[24] < heights[0])

        // Frames at t+0.31s: every slot elapsed, lerp converges toward 2px.
        for _ in 0 ..< 15 {
            heights = model.update(barCount: 48, maxHeight: 80, level: 0, now: start.addingTimeInterval(0.31))
        }
        #expect(heights[24] < 5)

        // After the stagger + lerp tail the model returns to idle.
        _ = model.update(barCount: 48, maxHeight: 80, level: 0, now: start.addingTimeInterval(1.0))
        #expect(model.state == .idle)
    }
}
