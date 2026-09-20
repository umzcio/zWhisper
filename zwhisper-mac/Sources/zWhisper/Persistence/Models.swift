import Foundation

// MARK: - history.json (architecture §7)

struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var modeID: UUID
    var rawTranscript: String
    var processedText: String
    /// Relative to Application Support; nil if the user disabled audio retention.
    var audioPath: String?
    /// Segment-level timings (word-level is a known WhisperKit gap, architecture §10.5).
    var segments: [TranscriptSegment]
    /// Per-entry reprocess history (§6.3 "Undo").
    var undoStack: [ProcessedVersion]
    var targetApp: String?
}

struct TranscriptSegment: Codable, Equatable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

struct ProcessedVersion: Codable, Equatable, Sendable {
    var modeID: UUID
    var text: String
    var createdAt: Date
}

// MARK: - vocabulary.json (architecture §7, spec §6.5)

struct VocabularyStore: Codable, Equatable, Sendable {
    var customWords: [Word]
    var replacements: [Replacement]

    static let empty = VocabularyStore(customWords: [], replacements: [])
}

struct Word: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    /// Drives the §6.5 hover tooltip ("Used N× · last: {when}").
    var useCount: Int
    var lastUsedAt: Date?
}

struct Replacement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var trigger: String
    var replacement: String
}

// MARK: - settings.json (architecture §7, spec §6.6 keys)

struct SettingsStore: Codable, Equatable, Sendable {
    var launchAtLogin = true
    var showInDock = false
    var startRecordingOnStatusItemClick = true
    var alwaysCloseWindowAfterDictation = true
    var theme: Theme = .dark
    var soundEffectsStyle: SoundEffectsStyle = .subtle
    var autoPaste = true
    var restoreClipboard = true
    var dynamicNormalization = true
    var silenceRemoval = true
    var silenceAggressiveness = 40
    /// Recording-length cap in seconds; nil = ∞ (§6.6 default 30s).
    var activeDuration: TimeInterval? = 30
    /// Whisper language code; "auto" = auto-detect (§6.6 Language).
    var language = "auto"
    /// §6.6 Language: translate-to-English switch (Whisper translate task).
    var translateToEnglish = false

    enum Theme: String, Codable, Sendable {
        case light, dark, system
    }

    enum SoundEffectsStyle: String, Codable, Sendable {
        case subtle, classic, none
    }
}
