import Foundation

typealias SFSymbolName = String

/// Architecture §3.4.
struct Mode: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: SFSymbolName
    var colorHex: String
    /// One-line card description (§6.2 grid).
    var description: String
    /// "AI Instructions" → system prompt (§6.2).
    var instructions: String
    /// Context toggles ("Super" badge, §6.2); capture itself is M7.
    var readsSelectedText: Bool
    var readsClipboard: Bool
    var autoActivationRules: [ActivationRule]
    /// ⌘1…⌘9 (§4.2).
    var shortcutIndex: Int?
    var isBuiltIn: Bool

    /// Voice Note short-circuits before any LLM call (§7 identity transform).
    var isIdentity: Bool {
        id == BuiltInModes.voiceNoteID
    }
}

/// §6.2 auto-activation: `When [app] is frontmost`. The domain field is stored
/// but inert in v1 (app-level matching only, architecture §6).
struct ActivationRule: Codable, Equatable, Sendable {
    var appName: String
    var domain: String?
}
