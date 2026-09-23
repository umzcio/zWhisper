import Foundation

/// Keychain-backed API keys for BYOK providers (§6.4/§8):
/// `kSecAttrAccessibleAfterFirstUnlock`, never on disk.
enum KeychainStore {
    private static let service = "app.zwhisper.zWhisper.providers"

    static func apiKey(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setAPIKey(_ key: String, for account: String) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let data = Data(key.utf8)
        if SecItemCopyMatching(attributes as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(attributes as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var item = attributes
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

/// BYOK provider metadata (§6.4 rows; the Models screen UI is M6).
struct CloudProviderConfig: Codable, Equatable, Sendable {
    var baseURL: String
    var model: String
    /// Keychain account holding the API key.
    var keychainAccount: String

    static let openAI = CloudProviderConfig(
        baseURL: "https://api.openai.com",
        model: "gpt-4o-mini",
        keychainAccount: "openai"
    )
}

/// Architecture §6 backend 2: OpenAI-compatible chat-completions over
/// `URLSession` (`/v1/chat/completions`, SSE streaming). Optional extra —
/// never an OS-version fallback (§2).
struct CloudLLMBackend: ModeBackend {
    let config: CloudProviderConfig
    let apiKey: String
    let session: URLSession

    init(config: CloudProviderConfig, apiKey: String, session: URLSession = .shared) {
        self.config = config
        self.apiKey = apiKey
        self.session = session
    }

    func stream(raw: String, mode: Mode, context: CapturedContext?, personalContext: String? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: URL(string: config.baseURL + "/v1/chat/completions")!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let body: [String: Any] = [
                        "model": config.model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": ModePrompt.instructions(for: mode, personalContext: personalContext)],
                            ["role": "user", "content": ModePrompt.build(raw: raw, mode: mode, context: context)],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw ModeProcessingError.intelligenceUnavailable
                    }

                    var accumulated = ""
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String
                        else { continue }
                        accumulated += content
                        continuation.yield(accumulated)
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
