import AVFAudio
import Foundation
import Testing
@testable import zWhisper

private func pcmBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() {
        buffer.floatChannelData![0][index] = sample
    }
    return buffer
}

private func bodyText(_ request: URLRequest) -> String {
    String(decoding: request.httpBody ?? Data(), as: UTF8.self)
}

private func hasField(_ body: String, _ name: String, _ value: String) -> Bool {
    body.contains("name=\"\(name)\"\r\n\r\n\(value)\r\n")
}

private final class HTTPStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var failure: URLError?
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Cloud transcription requests", .serialized)
struct CloudTranscriberTests {
    private func transcriber(_ provider: CloudTranscriptionProvider) -> CloudTranscriber {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStub.self]
        return CloudTranscriber(provider: provider, apiKey: "k-1", session: URLSession(configuration: config))
    }

    @Test("OpenAI: gpt-transcribe, languages[] and keywords[], bearer auth, the audio attached")
    func openAIRequest() throws {
        let request = try #require(transcriber(.openAI).makeRequest(wav: Data("WAVBYTES".utf8), language: "es", vocabulary: ["Zach", "UM"]))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = bodyText(request)
        #expect(hasField(body, "model", "gpt-transcribe"))
        #expect(hasField(body, "languages[]", "es"))
        #expect(hasField(body, "keywords[]", "Zach"))
        #expect(hasField(body, "keywords[]", "UM"))
        #expect(!body.contains("name=\"language\""))
        #expect(body.contains("filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\nWAVBYTES\r\n"))
    }

    @Test("Groq: whisper-large-v3 on its own host, vocabulary as a prompt, auto language omitted")
    func groqRequest() throws {
        let request = try #require(transcriber(.groq).makeRequest(wav: Data(), language: nil, vocabulary: ["Zach", "UM"]))
        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k-1")
        let body = bodyText(request)
        #expect(hasField(body, "model", "whisper-large-v3"))
        #expect(hasField(body, "prompt", "Zach, UM"))
        #expect(!body.contains("name=\"language\""))
    }

    @Test("Deepgram: nova-3, token auth, raw WAV body, escaped repeated keyterms")
    func deepgramRequest() throws {
        let wav = Data("WAVBYTES".utf8)
        let request = try #require(transcriber(.deepgram).makeRequest(wav: wav, language: "fr", vocabulary: ["C++", "New York"]))
        let query = request.url?.query(percentEncoded: true) ?? ""
        #expect(request.url?.host() == "api.deepgram.com")
        #expect(request.url?.path() == "/v1/listen")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token k-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "audio/wav")
        #expect(request.httpBody == wav)
        #expect(query.contains("model=nova-3"))
        #expect(query.contains("smart_format=true"))
        #expect(query.contains("language=fr"))
        #expect(query.contains("keyterm=C%2B%2B"))
        #expect(query.contains("keyterm=New%20York"))
    }

    @Test("Deepgram auto-detect uses multi")
    func deepgramAuto() {
        let query = transcriber(.deepgram).makeRequest(wav: Data(), language: nil, vocabulary: [])?.url?.query() ?? ""
        #expect(query.contains("language=multi"))
    }

    private func selfHosted(_ server: SelfHostedServer?, key: String? = nil) -> CloudTranscriber {
        CloudTranscriber(provider: .selfHosted, apiKey: key, server: server)
    }

    @Test("self-hosted endpoints accept the server root or its /v1 URL; junk is rejected")
    func selfHostedEndpoints() {
        func endpoint(_ base: String, _ style: SelfHostedServer.APIStyle = .transcriptions) -> String? {
            SelfHostedServer(baseURL: base, model: "m", style: style).endpoint?.absoluteString
        }
        #expect(endpoint("http://gpu.local:8000") == "http://gpu.local:8000/v1/audio/transcriptions")
        #expect(endpoint(" http://gpu.local:8000/v1/ ") == "http://gpu.local:8000/v1/audio/transcriptions")
        #expect(endpoint("https://asr.example.com/v1", .chat) == "https://asr.example.com/v1/chat/completions")
        #expect(endpoint("gpu.local:8000") == nil)
        #expect(endpoint("ftp://gpu.local") == nil)
        #expect(endpoint("") == nil)
        #expect(!SelfHostedServer(baseURL: "http://gpu.local", model: "  ").isValid)
    }

    @Test("self-hosted transcriptions: the configured model, no auth header without a key")
    func selfHostedTranscriptions() throws {
        let server = SelfHostedServer(baseURL: "http://10.0.0.5:8000", model: "openai/whisper-large-v3")
        let request = try #require(selfHosted(server).makeRequest(wav: Data(), language: "de", vocabulary: ["Zach"]))
        #expect(request.url?.absoluteString == "http://10.0.0.5:8000/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = bodyText(request)
        #expect(hasField(body, "model", "openai/whisper-large-v3"))
        #expect(hasField(body, "language", "de"))
        #expect(hasField(body, "prompt", "Zach"))
        let keyed = try #require(selfHosted(server, key: "secret").makeRequest(wav: Data(), language: nil, vocabulary: []))
        #expect(keyed.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(selfHosted(nil).makeRequest(wav: Data(), language: nil, vocabulary: []) == nil)
    }

    @Test("self-hosted chat: the audio as an input_audio part, the task and terms as text")
    func selfHostedChat() throws {
        let server = SelfHostedServer(baseURL: "http://gpu.local:8000", model: "nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B", style: .chat)
        let wav = Data("WAV".utf8)
        let request = try #require(selfHosted(server).makeRequest(wav: wav, language: "en", vocabulary: ["Zach", "UM"]))
        #expect(request.url?.absoluteString == "http://gpu.local:8000/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(json["model"] as? String == "nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B")
        #expect(json["temperature"] as? Int == 0)
        let message = try #require((json["messages"] as? [[String: Any]])?.first)
        let parts = try #require(message["content"] as? [[String: Any]])
        let text = try #require(parts.first?["text"] as? String)
        #expect(text.hasPrefix("Transcribe with punctuation and capitalization."))
        #expect(text.contains("Context terms: Zach, UM."))
        let audio = try #require(parts.last?["input_audio"] as? [String: String])
        #expect(audio == ["data": wav.base64EncodedString(), "format": "wav"])

        let reply = #"{"choices":[{"message":{"role":"assistant","content":"hello there"}}]}"#
        #expect(try CloudTranscriber.transcript(from: Data(reply.utf8), provider: .selfHosted, style: .chat) == "hello there")
    }

    @Test("plain http to a non-local host maps to a clear error")
    func insecureConnection() async {
        HTTPStub.failure = URLError(.appTransportSecurityRequiresSecureConnection)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStub.self]
        let server = SelfHostedServer(baseURL: "http://asr.example.com", model: "m")
        let transcriber = CloudTranscriber(provider: .selfHosted, apiKey: nil, server: server, session: URLSession(configuration: config))
        await #expect(throws: CloudTranscriptionError.insecureConnection) {
            try await transcriber.transcribe(wav: Data(), language: nil, vocabulary: [])
        }
        HTTPStub.failure = nil
    }

    @Test("terms that would fail the whole request are dropped, and the list is capped")
    func vocabularyLimits() {
        #expect(CloudTranscriber.usableTerms([" Zach ", "", "a<b", "c>d", "e\nf", "g\rh"]) == ["Zach"])
        #expect(CloudTranscriber.usableTerms((0 ..< 80).map { "w\($0)" }).count == 50)
    }

    @Test("responses parse per provider")
    func parsing() throws {
        #expect(try CloudTranscriber.transcript(from: Data(#"{"text":"hi","languages":[]}"#.utf8), provider: .openAI) == "hi")
        #expect(try CloudTranscriber.transcript(from: Data(#"{"text":"hey"}"#.utf8), provider: .groq) == "hey")
        let deepgram = #"{"results":{"channels":[{"alternatives":[{"transcript":"yo"}]}]}}"#
        #expect(try CloudTranscriber.transcript(from: Data(deepgram.utf8), provider: .deepgram) == "yo")
        #expect(throws: CloudTranscriptionError.unexpectedResponse) {
            try CloudTranscriber.transcript(from: Data("{}".utf8), provider: .deepgram)
        }
    }

    @Test("status codes and network failures map to actionable errors")
    func errors() async throws {
        HTTPStub.failure = nil
        HTTPStub.body = Data(#"{"text":"ok"}"#.utf8)
        HTTPStub.status = 200
        #expect(try await transcriber(.groq).transcribe(wav: Data(), language: nil, vocabulary: []) == "ok")
        let cases: [(Int, CloudTranscriptionError)] = [
            (401, .invalidKey), (403, .invalidKey), (402, .quotaOrRateLimit), (429, .quotaOrRateLimit),
            (400, .rejected(status: 400)), (500, .serverError(status: 500)),
        ]
        for (status, expected) in cases {
            HTTPStub.status = status
            await #expect(throws: expected) {
                try await transcriber(.groq).transcribe(wav: Data(), language: nil, vocabulary: [])
            }
        }
        HTTPStub.failure = URLError(.notConnectedToInternet)
        await #expect(throws: CloudTranscriptionError.unreachable) {
            try await transcriber(.groq).transcribe(wav: Data(), language: nil, vocabulary: [])
        }
        HTTPStub.failure = nil
    }

    @Test("audio past a provider's limit isn't uploaded")
    func uploadLimit() async {
        let before = HTTPStub.requests
        await #expect(throws: CloudTranscriptionError.audioTooLong) {
            try await transcriber(.openAI).transcribe(wav: Data(count: 25_000_001), language: nil, vocabulary: [])
        }
        #expect(HTTPStub.requests == before)
    }

    @Test("WAV is valid 16-bit mono PCM and clips out-of-range samples")
    func wavEncoding() {
        let wav = WAVEncoder.data(from: pcmBuffer([0, 1, -1, 2]))
        #expect(wav.count == 44 + 8)
        #expect(String(decoding: wav[0 ..< 4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8 ..< 16], as: UTF8.self) == "WAVEfmt ")
        func u32(_ at: Int) -> UInt32 { wav[at ..< at + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        func i16(_ at: Int) -> Int16 { Int16(bitPattern: UInt16(wav[at]) | UInt16(wav[at + 1]) << 8) }
        #expect(u32(4) == 36 + 8)
        #expect(u32(24) == 16_000)
        #expect(u32(28) == 32_000)
        #expect(u32(40) == 8)
        #expect(i16(44) == 0)
        #expect(i16(46) == Int16.max)
        #expect(i16(48) == -Int16.max)
        #expect(i16(50) == Int16.max)
    }
}

private actor MockCloudTranscriber: CloudTranscribing {
    private(set) var calls: [(language: String?, vocabulary: [String], bytes: Int)] = []
    var result: Result<String, Error> = .success("  from the cloud \n")

    func setResult(_ result: Result<String, Error>) {
        self.result = result
    }

    func transcribe(wav: Data, language: String?, vocabulary: [String]) async throws -> String {
        calls.append((language, vocabulary, wav.count))
        return try result.get()
    }
}

@Suite("AppState cloud transcription")
@MainActor
struct AppStateCloudTests {
    private func makeState(keys: Set<String> = ["groq"]) async -> (AppState, MockTranscriptionEngine, MockCloudTranscriber, MockPasteController) {
        let transcription = MockTranscriptionEngine()
        let cloud = MockCloudTranscriber()
        let paste = MockPasteController()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        let state = AppState(
            audio: MockAudioCaptureEngine(),
            transcription: transcription,
            paste: paste,
            persistence: PersistenceStore(directory: dir),
            requestRecordPermission: { true },
            cloudAPIKey: { keys.contains($0) ? "k-\($0)" : nil },
            makeCloudTranscriber: { _, _, _ in cloud }
        )
        await state.prepareTranscription()
        return (state, transcription, cloud, paste)
    }

    private func dictate(_ state: AppState) async {
        state.startDictation()
        try? await Task.sleep(for: .milliseconds(100))
        state.stopDictation()
        try? await Task.sleep(for: .milliseconds(300))
    }

    @Test("by default no audio reaches a provider, even with a key saved")
    func localByDefault() async {
        let (state, transcription, cloud, paste) = await makeState()
        await dictate(state)
        #expect(await cloud.calls.isEmpty)
        #expect(await transcription.finalCalls == 1)
        #expect(paste.pastedText != nil)
    }

    @Test("a provider can't be set active without its key")
    func needsKey() async {
        let (state, _, _, _) = await makeState(keys: [])
        state.setActiveCloudModel(CloudTranscriptionProvider.groq.rawValue)
        #expect(state.activeCloudProvider == nil)
        #expect(state.modelStates[CloudTranscriptionProvider.groq.rawValue] != .active)
    }

    @Test("an active provider does the final pass, and the transcript reaches paste and history")
    func cloudFinalPass() async {
        let (state, transcription, cloud, paste) = await makeState()
        state.settings.language = "es"
        state.setActiveCloudModel(CloudTranscriptionProvider.groq.rawValue)
        #expect(state.modelStates[CloudTranscriptionProvider.groq.rawValue] == .active)
        await dictate(state)
        let calls = await cloud.calls
        #expect(calls.count == 1)
        #expect(calls.first?.language == "es")
        #expect(await transcription.finalCalls == 0)
        #expect(await transcription.resetCalls == 1)
        #expect(paste.pastedText == "from the cloud")
        #expect(state.history.first?.segments.first?.text == "from the cloud")
        #expect(state.cloudFailureMessage == nil)
    }

    @Test("a cloud failure falls back to the local model and says so")
    func fallback() async {
        let (state, transcription, cloud, paste) = await makeState()
        await cloud.setResult(.failure(CloudTranscriptionError.invalidKey))
        state.setActiveCloudModel(CloudTranscriptionProvider.groq.rawValue)
        await dictate(state)
        #expect(await transcription.finalCalls == 1)
        #expect(paste.pastedText == "the quick brown fox")
        #expect(state.cloudFailureMessage == "Groq rejected your API key.")
        #expect(state.pasteSubtitle.hasSuffix("· used on-device"))

        await cloud.setResult(.success("back"))
        try? await Task.sleep(for: .milliseconds(900)) // past the 700ms pasted state
        #expect(state.phase == .idle)
        await dictate(state)
        #expect(paste.pastedText == "back")
        #expect(state.cloudFailureMessage == nil)
        #expect(!state.pasteSubtitle.contains("on-device"))
    }

    @Test("with no local model either, the failure is shown instead of pasting")
    func noFallback() async {
        let (state, transcription, cloud, paste) = await makeState()
        await cloud.setResult(.failure(CloudTranscriptionError.unreachable))
        await transcription.setFinalError(TranscriptionError.modelNotLoaded)
        state.setActiveCloudModel(CloudTranscriptionProvider.groq.rawValue)
        await dictate(state)
        #expect(state.transcriptionFailed)
        #expect(state.cloudFailureMessage == "Couldn't reach Groq.")
        #expect(paste.pastedText == nil)
    }

    @Test("translate-to-English stays local")
    func translateIsLocal() async {
        let (state, transcription, cloud, _) = await makeState()
        state.settings.translateToEnglish = true
        state.setActiveCloudModel(CloudTranscriptionProvider.groq.rawValue)
        await dictate(state)
        #expect(await cloud.calls.isEmpty)
        #expect(await transcription.finalCalls == 1)
    }

    @Test("the choice survives a relaunch, and is dropped if the key is gone")
    func persistence() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        let store = PersistenceStore(directory: dir)
        var saved = ModelPreferences()
        saved.activeCloudID = CloudTranscriptionProvider.groq.rawValue
        try await store.save(saved, to: "models.json")

        func launch(keys: Set<String>) async -> AppState {
            let state = AppState(
                audio: MockAudioCaptureEngine(),
                transcription: MockTranscriptionEngine(),
                paste: MockPasteController(),
                persistence: store,
                requestRecordPermission: { true },
                cloudAPIKey: { keys.contains($0) ? "k" : nil },
                makeCloudTranscriber: { _, _, _ in MockCloudTranscriber() }
            )
            await state.loadModelPreferences()
            return state
        }
        let withKey = await launch(keys: ["groq"])
        #expect(withKey.activeCloudProvider == .groq)
        #expect(withKey.modelStates[CloudTranscriptionProvider.groq.rawValue] == .active)
        let withoutKey = await launch(keys: [])
        #expect(withoutKey.activeCloudProvider == nil)
    }

    @Test("self-hosted needs a valid server, not a key, and is used once active")
    func selfHostedFlow() async {
        let (state, transcription, cloud, paste) = await makeState(keys: [])
        let selfHostedID = CloudTranscriptionProvider.selfHosted.rawValue
        state.setActiveCloudModel(selfHostedID)
        #expect(state.activeCloudProvider == nil)

        state.saveSelfHostedServer(SelfHostedServer(baseURL: "http://gpu.local:8000", model: "whisper"), apiKey: "")
        #expect(state.isCloudProviderReady(.selfHosted))
        state.setActiveCloudModel(selfHostedID)
        #expect(state.activeCloudProvider == .selfHosted)
        await dictate(state)
        #expect(await cloud.calls.count == 1)
        #expect(await transcription.finalCalls == 0)
        #expect(paste.pastedText == "from the cloud")
    }

    @Test("an old models.json without the cloud field still loads")
    func oldPreferences() throws {
        let data = Data(#"{"favoriteIDs":["tiny"],"activeLocalID":"small"}"#.utf8)
        let decoded = try JSONDecoder().decode(ModelPreferences.self, from: data)
        #expect(decoded.activeLocalID == "small")
        #expect(decoded.activeCloudID == nil)
    }
}
