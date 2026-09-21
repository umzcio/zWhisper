import Foundation
import Testing
@testable import zWhisper

final class MockModeProcessor: ModeProcessorProtocol, @unchecked Sendable {
    private(set) var calls: [(raw: String, mode: Mode)] = []
    var chunks = ["Dear team,", "Dear team,\n\nThe meeting has been moved to Friday.", "Dear team,\n\nThe meeting has been moved to Friday.\n\nBest, Alex"]
    var error: Error?

    func process(raw: String, mode: Mode, context: CapturedContext?) -> AsyncThrowingStream<String, Error> {
        calls.append((raw, mode))
        let chunks = self.chunks
        let error = self.error
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

/// Backend-tracking processor for backend-selection tests.
final class TrackingBackend: ModeBackend, @unchecked Sendable {
    private(set) var calls = 0
    let text: String

    init(text: String) {
        self.text = text
    }

    func stream(raw: String, mode: Mode, context: CapturedContext?) -> AsyncThrowingStream<String, Error> {
        calls += 1
        let text = self.text
        return AsyncThrowingStream { continuation in
            continuation.yield(text)
            continuation.finish()
        }
    }
}

@Suite("ModeProcessor (architecture §6)")
struct ModeProcessorTests {
    @Test("Voice Note short-circuits before any backend (§7 identity)")
    func identity() async throws {
        let foundation = TrackingBackend(text: "llm")
        let processor = ModeProcessor(foundationBackend: foundation, cloudBackend: nil)
        var results: [String] = []
        for try await chunk in processor.process(raw: "raw words", mode: BuiltInModes.voiceNote, context: nil) {
            results.append(chunk)
        }
        #expect(results == ["raw words"])
        #expect(foundation.calls == 0)
    }

    @Test("no backend configured → actionable intelligenceUnavailable error (§8)")
    func noBackend() async throws {
        let processor = ModeProcessor(foundationBackend: nil, cloudBackend: nil)
        do {
            for try await _ in processor.process(raw: "raw", mode: BuiltInModes.email, context: nil) {}
            Issue.record("expected throw")
        } catch {
            #expect(error as? ModeProcessingError == .intelligenceUnavailable)
        }
    }

    @Test("Foundation Models preferred; cloud used when it is the only backend")
    func backendChoice() async throws {
        let foundation = TrackingBackend(text: "f")
        let cloud = TrackingBackend(text: "c")

        let both = ModeProcessor(foundationBackend: foundation, cloudBackend: cloud)
        for try await _ in both.process(raw: "raw", mode: BuiltInModes.email, context: nil) {}
        #expect(foundation.calls == 1)
        #expect(cloud.calls == 0)

        let cloudOnly = ModeProcessor(foundationBackend: nil, cloudBackend: cloud)
        for try await _ in cloudOnly.process(raw: "raw", mode: BuiltInModes.email, context: nil) {}
        #expect(cloud.calls == 1)
    }

    @Test("context is embedded only for context-enabled modes (§6)")
    func promptContext() {
        let context = CapturedContext(frontmostApp: "Notes", selectedText: "sel", clipboard: "clip", capturedAt: .now)
        let superPrompt = ModePrompt.build(raw: "raw", mode: BuiltInModes.superMode, context: context)
        #expect(superPrompt.contains("selected text in Notes"))
        #expect(superPrompt.contains("clipboard"))
        let emailPrompt = ModePrompt.build(raw: "raw", mode: BuiltInModes.email, context: context)
        #expect(!emailPrompt.contains("selected text"))
    }
}

@Suite("CloudLLMBackend SSE (§6 backend 2)")
struct CloudLLMBackendTests {
    @Test("SSE deltas accumulate into cumulative yields")
    func sse() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" world"}}]}

        data: [DONE]


        """
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEStub.self]
        SSEStub.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(sse.utf8))
        }
        let backend = CloudLLMBackend(
            config: CloudProviderConfig(baseURL: "https://example.test", model: "m", keychainAccount: "x"),
            apiKey: "sk-test",
            session: URLSession(configuration: config)
        )
        var yields: [String] = []
        for try await chunk in backend.stream(raw: "raw", mode: BuiltInModes.email, context: nil) {
            yields.append(chunk)
        }
        #expect(yields == ["Hello", "Hello world"])
    }
}

private final class SSEStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (response, data) = Self.handler!(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("AppState modes flow (M5)")
@MainActor
struct ModeFlowTests {
    private func makeState() async -> (AppState, MockAudioCaptureEngine, MockTranscriptionEngine, MockModeProcessor, MockPasteController) {
        let audio = MockAudioCaptureEngine()
        let transcription = MockTranscriptionEngine()
        let processor = MockModeProcessor()
        let paste = MockPasteController()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        let state = AppState(
            audio: audio,
            transcription: transcription,
            modeProcessor: processor,
            paste: paste,
            persistence: PersistenceStore(directory: dir),
            requestRecordPermission: { true }
        )
        await state.prepareTranscription()
        return (state, audio, transcription, processor, paste)
    }

    private func dictate(_ state: AppState) async {
        state.startDictation()
        try? await Task.sleep(for: .milliseconds(100))
        state.stopDictation()
        try? await Task.sleep(for: .milliseconds(400))
    }

    @Test("Voice Note pastes the raw transcript without any LLM call (§7)")
    func voiceNoteIdentity() async throws {
        let (state, _, _, processor, paste) = await makeState()
        await dictate(state)
        #expect(processor.calls.isEmpty)
        #expect(paste.pastedText == "the quick brown fox")
        guard case .pasted = state.phase else {
            Issue.record("expected pasted, got \(state.phase)")
            return
        }
    }

    @Test("Email mode streams the rewrite into the teleprompter and pastes it")
    func emailProcessing() async throws {
        let (state, _, _, processor, paste) = await makeState()
        state.setActiveMode(BuiltInModes.email)
        await dictate(state)
        #expect(processor.calls.count == 1)
        #expect(processor.calls.first?.mode.id == BuiltInModes.emailID)
        #expect(processor.calls.first?.raw == "the quick brown fox")
        let final = processor.chunks.last!
        #expect(state.processedText == final)
        #expect(paste.pastedText == final)
        let entry = try #require(state.history.first)
        #expect(entry.modeID == BuiltInModes.emailID)
        #expect(entry.rawTranscript == "the quick brown fox")
        #expect(entry.processedText == final)
    }

    @Test("⌘1–7 live switch during recording: processing uses the mode at stop time (§4.2)")
    func liveSwitch() async throws {
        let (state, _, _, processor, _) = await makeState()
        state.startDictation()
        try await Task.sleep(for: .milliseconds(100))
        state.switchMode(shortcutIndex: 2)
        #expect(state.activeMode.id == BuiltInModes.messageID)
        #expect(state.modePulseTrigger == 1)
        state.stopDictation()
        try await Task.sleep(for: .milliseconds(400))
        #expect(processor.calls.first?.mode.id == BuiltInModes.messageID)
    }

    @Test("cycle mode advances in ⌘-index order")
    func cycle() async {
        let (state, _, _, _, _) = await makeState()
        #expect(state.activeMode.id == BuiltInModes.voiceNoteID) // ⌘5
        state.cycleMode()
        #expect(state.activeMode.id == BuiltInModes.writeForMeID) // ⌘6
        state.cycleMode()
        #expect(state.activeMode.id == BuiltInModes.superModeID) // ⌘7
        state.cycleMode()
        #expect(state.activeMode.id == BuiltInModes.emailID) // wraps to ⌘1
    }

    @Test("Reprocess: undo paste, advance mode, re-paste, history undo stack (§4.3)")
    func reprocess() async throws {
        let (state, _, _, processor, paste) = await makeState()
        state.setActiveMode(BuiltInModes.email)
        await dictate(state)
        #expect(paste.undoCalls == 0)

        state.reprocess()
        try await Task.sleep(for: .milliseconds(400))
        #expect(state.activeMode.id == BuiltInModes.messageID)
        #expect(paste.undoCalls == 1)
        #expect(processor.calls.count == 2)
        #expect(processor.calls.last?.mode.id == BuiltInModes.messageID)

        let entry = try #require(state.history.first)
        #expect(entry.modeID == BuiltInModes.messageID)
        #expect(entry.undoStack.count == 1)
        #expect(entry.undoStack.first?.modeID == BuiltInModes.emailID)
        #expect(entry.undoStack.first?.text == processor.chunks.last)
        #expect(state.history.count == 1)
    }

    @Test("Reprocess with auto-paste off: re-runs processing without a paste receipt")
    func reprocessAutoPasteOff() async throws {
        let (state, _, _, processor, paste) = await makeState()
        state.settings.autoPaste = false
        state.setActiveMode(BuiltInModes.email)
        await dictate(state)
        #expect(paste.copiedText == processor.chunks.last)

        state.reprocess()
        try await Task.sleep(for: .milliseconds(400))
        #expect(state.activeMode.id == BuiltInModes.messageID)
        #expect(processor.calls.count == 2)
        #expect(paste.undoCalls == 0) // nothing was pasted — nothing to undo
        let entry = try #require(state.history.first)
        #expect(entry.modeID == BuiltInModes.messageID)
        #expect(entry.undoStack.count == 1)
        #expect(state.history.count == 1)
    }

    @Test("Reprocess after deleting the history entry targets nothing and still re-pastes")
    func reprocessAfterDeletingEntry() async throws {
        let (state, _, _, processor, _) = await makeState()
        state.setActiveMode(BuiltInModes.email)
        await dictate(state)
        let entry = try #require(state.history.first)
        state.deleteHistory(id: entry.id)
        #expect(state.history.isEmpty)

        state.reprocess()
        try await Task.sleep(for: .milliseconds(400))
        #expect(processor.calls.count == 2)
        #expect(processor.calls.last?.mode.id == BuiltInModes.messageID)
        // No unrelated entry gained an undo version; no new entry appended.
        #expect(state.history.isEmpty)
    }

    @Test("push-to-talk: hold starts with the flag, release stops + pastes (§4.1)")
    func pushToTalk() async throws {
        let (state, _, _, _, paste) = await makeState()
        state.startPushToTalk()
        try await Task.sleep(for: .milliseconds(100))
        guard case .recording = state.phase else {
            Issue.record("expected recording")
            return
        }
        #expect(state.holdToTalkActive)

        state.stopPushToTalk()
        try await Task.sleep(for: .milliseconds(400))
        #expect(!state.holdToTalkActive)
        guard case .pasted = state.phase else {
            Issue.record("expected pasted, got \(state.phase)")
            return
        }
        #expect(paste.pastedText == "the quick brown fox")
    }

    @Test("PTT release without a PTT start does not stop a hotkey-started recording")
    func pttReleaseGuard() async throws {
        let (state, _, _, _, _) = await makeState()
        state.toggleDictation() // ⌥⇧Space start, not PTT
        try await Task.sleep(for: .milliseconds(100))
        state.stopPushToTalk() // stale release — must not stop
        try await Task.sleep(for: .milliseconds(100))
        guard case .recording = state.phase else {
            Issue.record("expected recording to continue")
            return
        }
        #expect(!state.holdToTalkActive)
        state.stopDictation()
    }

    @Test("Esc clears the hold-to-talk flag")
    func pttCancel() async throws {
        let (state, _, _, _, _) = await makeState()
        state.startPushToTalk()
        try await Task.sleep(for: .milliseconds(100))
        state.cancel()
        #expect(!state.holdToTalkActive)
        #expect(state.phase == .idle)
    }

    @Test("processing failure (no backend) → actionable state, no paste (§8)")
    func processingFailure() async throws {
        let (state, _, _, processor, paste) = await makeState()
        processor.error = ModeProcessingError.intelligenceUnavailable
        state.setActiveMode(BuiltInModes.email)
        await dictate(state)
        #expect(state.phase == .idle)
        #expect(state.modeProcessingFailed)
        #expect(state.failedModeName == "Email")
        #expect(paste.pastedText == nil)
        #expect(state.history.isEmpty)
    }

    @Test("auto-activation rules match the frontmost app, app-level only (§6.2)")
    func autoActivation() async {
        let (state, _, _, _, _) = await makeState()
        await state.loadModes()
        #expect(state.modeMatchingRules(frontmostApp: "Mail") == nil)

        var slackMode = state.modes.first { $0.id == BuiltInModes.slackUpdateID }!
        slackMode.autoActivationRules = [ActivationRule(appName: "Slack", domain: nil)]
        state.updateCustomMode(slackMode)

        #expect(state.modeMatchingRules(frontmostApp: "Slack")?.id == BuiltInModes.slackUpdateID)
        #expect(state.modeMatchingRules(frontmostApp: "Mail") == nil)
        // Domain is stored but inert in v1: a Safari-domain rule still matches app-level only.
        let safari = Mode(
            id: UUID(),
            name: "Safari Test",
            icon: "mic",
            colorHex: "#0A84FF",
            description: "",
            instructions: "",
            readsSelectedText: false,
            readsClipboard: false,
            autoActivationRules: [ActivationRule(appName: "Safari", domain: "github.com")],
            shortcutIndex: nil,
            isBuiltIn: false
        )
        state.addCustomMode(safari)
        #expect(state.modeMatchingRules(frontmostApp: "Safari") != nil)
    }
}
