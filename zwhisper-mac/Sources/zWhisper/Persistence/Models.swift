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
    /// §6.6: "Saved to History" result toast after each dictation. Off by
    /// default (1.0.11) — the popover's pasted caption is enough feedback.
    var showResultToast = false
    var dynamicNormalization = true
    var silenceRemoval = true
    var silenceAggressiveness = 40
    /// Backstop recording-length ceiling in seconds; nil = ∞ (§6.6). The
    /// normal ending is trailing silence (1.0.8+), this only bounds stuck
    /// recordings — legacy default was a 30s wall-clock length.
    var activeDuration: TimeInterval? = 300
    /// Whisper language code; "auto" = auto-detect (§6.6 Language).
    var language = "auto"
    /// §6.6 Sound: AVCaptureDevice UID of the chosen input; nil = system default.
    var inputDeviceUID: String? = nil
    /// §6.6 Language: translate-to-English switch (Whisper translate task).
    var translateToEnglish = false
    /// Where the dictation indicator lives: floating top-center (default) or a
    /// persistent compact pill docked at the bottom-right above the Dock.
    var popoverPlacement: PopoverPlacement = .top
    /// §6.6 "About you": free-text user context (role, employer, vocabulary
    /// like "UM = University of Montana") injected into every mode's prompt.
    var personalContext: String = ""

    /// Tolerant decoder: synthesized Codable throws on any missing key, which
    /// would reset every existing user's settings whenever a field is added.
    /// Decode-if-present with the property defaults instead.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? false
        startRecordingOnStatusItemClick = try c.decodeIfPresent(Bool.self, forKey: .startRecordingOnStatusItemClick) ?? true
        alwaysCloseWindowAfterDictation = try c.decodeIfPresent(Bool.self, forKey: .alwaysCloseWindowAfterDictation) ?? true
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? .dark
        soundEffectsStyle = try c.decodeIfPresent(SoundEffectsStyle.self, forKey: .soundEffectsStyle) ?? .subtle
        autoPaste = try c.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? true
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? true
        showResultToast = try c.decodeIfPresent(Bool.self, forKey: .showResultToast) ?? false
        dynamicNormalization = try c.decodeIfPresent(Bool.self, forKey: .dynamicNormalization) ?? true
        silenceRemoval = try c.decodeIfPresent(Bool.self, forKey: .silenceRemoval) ?? true
        silenceAggressiveness = try c.decodeIfPresent(Int.self, forKey: .silenceAggressiveness) ?? 40
        // Optional fields: absent means "user chose nil" (∞ / system default) —
        // never substitute a fresh-install default here.
        activeDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .activeDuration)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        translateToEnglish = try c.decodeIfPresent(Bool.self, forKey: .translateToEnglish) ?? false
        popoverPlacement = try c.decodeIfPresent(PopoverPlacement.self, forKey: .popoverPlacement) ?? .top
        inputDeviceUID = try c.decodeIfPresent(String.self, forKey: .inputDeviceUID)
        personalContext = try c.decodeIfPresent(String.self, forKey: .personalContext) ?? ""
    }

    init() {}

    enum PopoverPlacement: String, Codable, Sendable {
        case top, bottomRight
    }

    enum Theme: String, Codable, Sendable {
        case light, dark, system
    }

    enum SoundEffectsStyle: String, Codable, Sendable {
        case subtle, classic, none
    }
}
