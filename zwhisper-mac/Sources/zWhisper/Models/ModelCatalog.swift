import Foundation

/// §6.4 row model. DotMeter ratings are static catalog metadata (§3.8).
struct ModelCatalogEntry: Equatable, Identifiable, Sendable {
    /// WhisperKit variant string for Whisper rows, LocalModelFamily ids for the
    /// NVIDIA rows, stable slug for cloud rows.
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
        // Ids are literal variant strings — keying a row off
        // ModelDownloadManager.defaultModelName would duplicate "small" on
        // baseline M1/<16GB hardware (the default there IS small).
        // sizeLabel is the offline fallback; ModelDownloadManager.fetchSizeLabel
        // replaces it with the repo's real size on the Models screen.
        ModelCatalogEntry(id: "tiny", name: "Nano", engine: "Whisper Tiny", detail: "Fastest, good for short notes", sizeLabel: "77 MB", speedDots: 4, accuracyDots: 2, isCloud: false),
        ModelCatalogEntry(id: "small", name: "Fast", engine: "Whisper Small", detail: "Best balance", sizeLabel: "486 MB", speedDots: 3, accuracyDots: 3, isCloud: false),
        ModelCatalogEntry(id: "medium", name: "Pro", engine: "Whisper Medium", detail: "High accuracy, slower", sizeLabel: "1.5 GB", speedDots: 2, accuracyDots: 4, isCloud: false),
        ModelCatalogEntry(id: "large-v3-v20240930_626MB", name: "Ultra", engine: "Whisper Large v3", detail: "Maximum accuracy, long dictations", sizeLabel: "627 MB", speedDots: 1, accuracyDots: 5, isCloud: false),
        // NVIDIA models via FluidAudio (CoreML on the Neural Engine). Sizes
        // include Parakeet's 106 MB vocabulary-boosting model.
        ModelCatalogEntry(id: LocalModelFamily.parakeetID, name: "Parakeet", engine: "Parakeet TDT v3 Ultra", detail: "25 European languages, near-instant", sizeLabel: "738 MB", speedDots: 5, accuracyDots: 5, isCloud: false, badge: "New"),
        ModelCatalogEntry(id: LocalModelFamily.nemotronID, name: "Nemotron", engine: "NVIDIA Nemotron 3.5 Streaming", detail: "True streaming, 40 languages", sizeLabel: "664 MB", speedDots: 4, accuracyDots: 4, isCloud: false, badge: "New"),
    ]

    /// Ids are CloudTranscriptionProvider raw values. Prices are for each
    /// provider's model as sent by CloudTranscriber.
    static let clouds: [ModelCatalogEntry] = [
        ModelCatalogEntry(id: "openai-whisper", name: "GPT Transcribe", engine: "OpenAI", detail: "OpenAI's recommended transcription model", sizeLabel: "—", speedDots: 3, accuracyDots: 5, isCloud: true, provider: "OpenAI", priceHint: "~$0.27/hr"),
        ModelCatalogEntry(id: "deepgram-nova", name: "Nova-3", engine: "Deepgram", detail: "Deepgram's general transcription model", sizeLabel: "—", speedDots: 4, accuracyDots: 4, isCloud: true, provider: "Deepgram", priceHint: "~$0.26-0.31/hr"),
        ModelCatalogEntry(id: "self-hosted", name: "Self-hosted", engine: "Your server", detail: "vLLM, SGLang-Omni, whisper.cpp or LocalAI on your own machine", sizeLabel: "—", speedDots: 3, accuracyDots: 3, isCloud: true, provider: "Self-hosted", priceHint: "your hardware"),
        ModelCatalogEntry(id: "groq-whisper", name: "Whisper Large v3", engine: "Groq", detail: "LPU-accelerated Whisper, near-instant", sizeLabel: "—", speedDots: 5, accuracyDots: 4, isCloud: true, provider: "Groq", badge: "Fastest cloud", priceHint: "~$0.11/hr"),
    ]

    static let all: [ModelCatalogEntry] = locals + clouds

    var runsOnThisMac: Bool { isCloud || LocalModelFamily(id: id).runsOnThisMac }
}

/// Which on-device engine runs a local catalog row.
enum LocalModelFamily: Equatable, Sendable {
    /// WhisperKit; the row id is the WhisperKit variant.
    case whisper
    /// Parakeet TDT 0.6B v3, Ultra post-training (FluidAudio `AsrModelVersion.ultra`).
    case parakeet
    /// Nemotron 3.5 ASR Streaming 0.6B, multilingual build, 1120 ms chunks.
    case nemotron

    static let parakeetID = "parakeet-tdt-v3"
    static let nemotronID = "nemotron-3.5-streaming"

    init(id: String) {
        switch id {
        case Self.parakeetID: self = .parakeet
        case Self.nemotronID: self = .nemotron
        default: self = .whisper
        }
    }

    /// Whisper is the only family that can translate to English.
    var canTranslate: Bool { self == .whisper }

    /// FluidAudio's models need the Neural Engine, so Apple Silicon only.
    var runsOnThisMac: Bool {
        #if arch(arm64)
        true
        #else
        self == .whisper
        #endif
    }
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
    /// When set, final transcripts come from this provider. activeLocalID stays
    /// as the live preview and fallback.
    var activeCloudID: String?
    var selfHostedServer: SelfHostedServer?
}
