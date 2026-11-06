import AVFAudio
import Foundation

/// Cloud speech-to-text providers (§6.4 cloud rows; raw values are the row ids).
/// Audio goes to a provider only after the user adds its key and sets it active.
enum CloudTranscriptionProvider: String, CaseIterable, Sendable {
    case openAI = "openai-whisper"
    case groq = "groq-whisper"
    case deepgram = "deepgram-nova"
    /// The user's own OpenAI-compatible server (vLLM, SGLang-Omni, whisper.cpp…).
    case selfHosted = "self-hosted"

    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .groq: "Groq"
        case .deepgram: "Deepgram"
        case .selfHosted: "Self-hosted"
        }
    }

    var keychainAccount: String {
        name.lowercased()
    }

    /// Documented upload cap; 16kHz WAV hits 25 MB at about 13 minutes.
    var maxUploadBytes: Int? {
        self == .openAI || self == .groq ? 25_000_000 : nil
    }
}

/// Where the self-hosted provider sends audio. Servers speak one of two APIs:
/// the transcriptions endpoint (vLLM for Whisper/Canary, SGLang-Omni, whisper.cpp,
/// LocalAI) or chat completions with an audio part (vLLM serving Nemotron 3.5
/// Transcribe, llama.cpp).
struct SelfHostedServer: Codable, Equatable, Sendable {
    enum APIStyle: String, Codable, CaseIterable, Sendable {
        case transcriptions, chat
    }

    var baseURL: String
    var model: String
    var style: APIStyle = .transcriptions

    /// Accepts the server root or its /v1 URL.
    var endpoint: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil
        else { return nil }
        let root = base.hasSuffix("/v1") ? base : base + "/v1"
        return URL(string: root + (style == .chat ? "/chat/completions" : "/audio/transcriptions"))
    }

    var isValid: Bool {
        endpoint != nil && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum CloudTranscriptionError: Error, Equatable {
    case invalidKey
    case quotaOrRateLimit
    case rejected(status: Int)
    case serverError(status: Int)
    case unreachable
    case insecureConnection
    case audioTooLong
    case unexpectedResponse

    func message(for provider: CloudTranscriptionProvider) -> String {
        switch self {
        case .invalidKey: "\(provider.name) rejected your API key."
        case .quotaOrRateLimit: "\(provider.name) is out of credit or rate limiting you."
        case .rejected: "\(provider.name) rejected the audio."
        case .serverError: "\(provider.name) is having problems."
        case .unreachable: "Couldn't reach \(provider.name)."
        case .insecureConnection: "\(provider.name) needs https, or a local network address."
        case .audioTooLong: "This recording is too long for \(provider.name)."
        case .unexpectedResponse: "\(provider.name) sent an unexpected response."
        }
    }
}

protocol CloudTranscribing: Sendable {
    func transcribe(wav: Data, language: String?, vocabulary: [String]) async throws -> String
}

struct CloudTranscriber: CloudTranscribing {
    /// Ephemeral so neither audio nor transcripts land in URLCache on disk.
    private static let defaultSession = URLSession(configuration: .ephemeral)

    let provider: CloudTranscriptionProvider
    /// Optional only for a self-hosted server.
    let apiKey: String?
    var server: SelfHostedServer?
    var session: URLSession = Self.defaultSession

    func transcribe(wav: Data, language: String?, vocabulary: [String]) async throws -> String {
        if let limit = provider.maxUploadBytes, wav.count > limit {
            throw CloudTranscriptionError.audioTooLong
        }
        guard let request = makeRequest(wav: wav, language: language, vocabulary: vocabulary) else {
            throw CloudTranscriptionError.unreachable
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            throw CloudTranscriptionError.insecureConnection
        } catch let error as URLError where error.code != .cancelled {
            throw CloudTranscriptionError.unreachable
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw CloudTranscriptionError.unexpectedResponse
        }
        switch status {
        case 200 ..< 300: return try Self.transcript(from: data, provider: provider, style: server?.style ?? .transcriptions)
        case 401, 403: throw CloudTranscriptionError.invalidKey
        case 402, 429: throw CloudTranscriptionError.quotaOrRateLimit
        case 400 ..< 500: throw CloudTranscriptionError.rejected(status: status)
        default: throw CloudTranscriptionError.serverError(status: status)
        }
    }

    func makeRequest(wav: Data, language: String?, vocabulary: [String]) -> URLRequest? {
        let terms = Self.usableTerms(vocabulary)
        switch provider {
        case .selfHosted:
            guard let server, server.isValid, let url = server.endpoint else { return nil }
            let model = server.model.trimmingCharacters(in: .whitespaces)
            if server.style == .chat {
                return chatRequest(to: url, model: model, wav: wav, language: language, terms: terms)
            }
            var fields = [("model", model), ("response_format", "json")]
            if let language { fields.append(("language", language)) }
            if !terms.isEmpty { fields.append(("prompt", String(terms.joined(separator: ", ").prefix(800)))) }
            var request = multipartRequest(to: url, fields: fields, wav: wav)
            request.timeoutInterval = 120 // a self-hosted model may be cold
            return request
        case .openAI:
            // gpt-transcribe takes languages[]/keywords[] instead of language/prompt.
            var fields = [("model", "gpt-transcribe")]
            if let language { fields.append(("languages[]", language)) }
            fields += terms.map { ("keywords[]", $0) }
            return multipartRequest(to: URL(string: "https://api.openai.com/v1/audio/transcriptions")!, fields: fields, wav: wav)
        case .groq:
            var fields = [("model", "whisper-large-v3"), ("response_format", "json")]
            if let language { fields.append(("language", language)) }
            if !terms.isEmpty { fields.append(("prompt", String(terms.joined(separator: ", ").prefix(800)))) }
            return multipartRequest(to: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!, fields: fields, wav: wav)
        case .deepgram:
            var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
            components.queryItems = [
                URLQueryItem(name: "model", value: "nova-3"),
                URLQueryItem(name: "smart_format", value: "true"),
                // "multi" for auto-detect: keyterms are documented to work with it.
                URLQueryItem(name: "language", value: language ?? "multi"),
            ] + terms.map { URLQueryItem(name: "keyterm", value: $0) }
            // URLComponents leaves "+" alone, and servers read it as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            var request = baseRequest(url: components.url!)
            request.setValue("Token \(apiKey ?? "")", forHTTPHeaderField: "Authorization")
            request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
            request.httpBody = wav
            return request
        }
    }

    /// OpenAI rejects the whole request over one bad keyword (`<`, `>`, line
    /// breaks); Deepgram advises at most 20-50 terms and errors past 500 tokens.
    static func usableTerms(_ vocabulary: [String]) -> [String] {
        let forbidden = CharacterSet(charactersIn: "<>\r\n")
        let terms = vocabulary
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.rangeOfCharacter(from: forbidden) == nil }
        return Array(terms.prefix(50))
    }

    static func transcript(from data: Data, provider: CloudTranscriptionProvider, style: SelfHostedServer.APIStyle = .transcriptions) throws -> String {
        struct TextResponse: Decodable {
            let text: String
        }
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        struct DeepgramResponse: Decodable {
            struct Results: Decodable { let channels: [Channel] }
            struct Channel: Decodable { let alternatives: [Alternative] }
            struct Alternative: Decodable { let transcript: String }
            let results: Results
        }
        let decoder = JSONDecoder()
        if provider == .selfHosted, style == .chat {
            guard let response = try? decoder.decode(ChatResponse.self, from: data),
                  let text = response.choices.first?.message.content
            else { throw CloudTranscriptionError.unexpectedResponse }
            return text
        }
        if provider == .deepgram {
            guard let response = try? decoder.decode(DeepgramResponse.self, from: data),
                  let text = response.results.channels.first?.alternatives.first?.transcript
            else { throw CloudTranscriptionError.unexpectedResponse }
            return text
        }
        guard let response = try? decoder.decode(TextResponse.self, from: data) else {
            throw CloudTranscriptionError.unexpectedResponse
        }
        return response.text
    }

    private func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        return request
    }

    /// Chat-style servers get the audio as an OpenAI `input_audio` part and the
    /// task as text (the prompt follows NVIDIA's Nemotron Transcribe card).
    private func chatRequest(to url: URL, model: String, wav: Data, language: String?, terms: [String]) -> URLRequest {
        var prompt = "Transcribe with punctuation and capitalization."
        if let language { prompt += " The audio is in language code \(language)." }
        if !terms.isEmpty { prompt += " Context terms: \(terms.joined(separator: ", "))." }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "input_audio", "input_audio": ["data": wav.base64EncodedString(), "format": "wav"]],
                ],
            ]],
        ]
        var request = baseRequest(url: url)
        request.timeoutInterval = 120
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func multipartRequest(to url: URL, fields: [(String, String)], wav: Data) -> URLRequest {
        let boundary = "zWhisper-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = baseRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}

/// 16-bit PCM WAV: every provider accepts it, and it needs no encoder state.
enum WAVEncoder {
    static func data(from buffer: AVAudioPCMBuffer) -> Data {
        let count = Int(buffer.frameLength)
        var samples = Data(capacity: count * 2)
        if count > 0, let channel = buffer.floatChannelData?[0] {
            for index in 0 ..< count {
                let clamped = max(-1, min(1, channel[index]))
                samples.append(littleEndian: Int16((clamped * Float(Int16.max)).rounded()))
            }
        }
        let sampleRate = UInt32(buffer.format.sampleRate)
        var wav = Data(capacity: 44 + samples.count)
        wav.append(Data("RIFF".utf8))
        wav.append(littleEndian: UInt32(36 + samples.count))
        wav.append(Data("WAVEfmt ".utf8))
        wav.append(littleEndian: UInt32(16))
        wav.append(littleEndian: UInt16(1)) // PCM
        wav.append(littleEndian: UInt16(1)) // mono
        wav.append(littleEndian: sampleRate)
        wav.append(littleEndian: sampleRate * 2)
        wav.append(littleEndian: UInt16(2))
        wav.append(littleEndian: UInt16(16))
        wav.append(Data("data".utf8))
        wav.append(littleEndian: UInt32(samples.count))
        wav.append(samples)
        return wav
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
