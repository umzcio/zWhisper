import Foundation

/// §6.4 row model. DotMeter ratings are static catalog metadata (§3.8).
struct ModelCatalogEntry: Equatable, Identifiable, Sendable {
    /// WhisperKit variant string for locals, stable slug for cloud rows.
    let id: String
    var name: String
    var engine: String
    var detail: String
    var sizeLabel: String
    var speedDots: Int
    var accuracyDots: Int
    var isCloud: Bool
    var provider: String?
    var badge: String?
    var priceHint: String?

    static let locals: [ModelCatalogEntry] = [
        // §8 tier mapping: tiny≈Nano, small≈Fast, medium≈Pro, large-v3≈Ultra.
        ModelCatalogEntry(id: "tiny", name: "Nano", engine: "Whisper v3", detail: "Fastest, good for short notes", sizeLabel: "466 MB", speedDots: 4, accuracyDots: 2, isCloud: false),
        ModelCatalogEntry(id: "small", name: "Fast", engine: "Whisper v3", detail: "Best balance — default", sizeLabel: "1.5 GB", speedDots: 3, accuracyDots: 3, isCloud: false),
        ModelCatalogEntry(id: "medium", name: "Pro", engine: "Whisper v3", detail: "High accuracy, slower", sizeLabel: "2.9 GB", speedDots: 2, accuracyDots: 4, isCloud: false),
        ModelCatalogEntry(id: ModelDownloadManager.defaultModelName, name: "Ultra", engine: "Whisper v3 Large", detail: "Maximum accuracy, long dictations", sizeLabel: "3.1 GB", speedDots: 1, accuracyDots: 5, isCloud: false),
    ]

    static let clouds: [ModelCatalogEntry] = [
        ModelCatalogEntry(id: "openai-whisper", name: "Whisper Large", engine: "OpenAI", detail: "OpenAI hosted transcription, pay per use", sizeLabel: "—", speedDots: 3, accuracyDots: 5, isCloud: true, provider: "OpenAI", priceHint: "~$0.36/hr"),
        ModelCatalogEntry(id: "deepgram-nova", name: "Nova-3", engine: "Deepgram", detail: "Streaming-first cloud transcription", sizeLabel: "—", speedDots: 4, accuracyDots: 4, isCloud: true, provider: "Deepgram", priceHint: "~$0.26/hr"),
        ModelCatalogEntry(id: "groq-whisper", name: "Whisper", engine: "Groq", detail: "LPU-accelerated Whisper, near-instant", sizeLabel: "—", speedDots: 5, accuracyDots: 4, isCloud: true, provider: "Groq", badge: "Fastest cloud", priceHint: "~$0.11/hr"),
        ModelCatalogEntry(id: "anthropic-speech", name: "Speech", engine: "Anthropic", detail: "Anthropic speech endpoint, billed to your key", sizeLabel: "—", speedDots: 3, accuracyDots: 4, isCloud: true, provider: "Anthropic", badge: "BYOK", priceHint: "your key"),
    ]

    static let all: [ModelCatalogEntry] = locals + clouds
}

/// §6.4 row states: none → queued → downloading → downloaded (+ active).
enum ModelDownloadStatus: Equatable {
    case none
    case queued
    case downloading(progress: Double, bytesPerSecond: Double)
    case downloaded
    case active
}

/// Persisted model preferences (models.json — §7 file list extension).
struct ModelPreferences: Codable, Equatable, Sendable {
    var favoriteIDs: [String] = []
    var activeLocalID: String?
}
