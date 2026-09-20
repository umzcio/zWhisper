import Foundation

/// Modes engine data (architecture §3.4/§6). The built-in library ships the
/// §6.2 seed with §7 script-bank colors, §8 icon mapping, and the prototype's
/// instruction copy; custom modes are full CRUD via the editor sheet (§6.2).
enum BuiltInModes {
    /// Stable IDs so history entries and modes.json overrides join across launches.
    static let emailID = UUID(uuidString: "E1A11B01-0001-4000-8000-000000000001")!
    static let messageID = UUID(uuidString: "E1A11B01-0002-4000-8000-000000000002")!
    static let noteID = UUID(uuidString: "E1A11B01-0003-4000-8000-000000000003")!
    static let meetingID = UUID(uuidString: "E1A11B01-0004-4000-8000-000000000004")!
    static let voiceNoteID = UUID(uuidString: "5A1E0A6E-0E1A-4E5A-9A0A-5E1A0A6E0E1A")!
    static let writeForMeID = UUID(uuidString: "E1A11B01-0006-4000-8000-000000000006")!
    static let superModeID = UUID(uuidString: "E1A11B01-0007-4000-8000-000000000007")!
    static let slackUpdateID = UUID(uuidString: "E1A11B01-0008-4000-8000-000000000008")!
    static let supportReplyID = UUID(uuidString: "E1A11B01-0009-4000-8000-000000000009")!

    /// §6.2 delta: the library card is "Voice Transcription"; the engine mode is "Voice Note".
    static let voiceNoteName = "Voice Note"

    static let email = Mode(
        id: emailID,
        name: "Email",
        icon: "envelope",
        colorHex: "#0A84FF",
        description: "Professional emails with greeting and sign-off",
        instructions: "Rewrite the transcription as a professional email. Keep it under 120 words. Sign off with my name.",
        readsSelectedText: false,
        readsClipboard: false,
        autoActivationRules: [],
        shortcutIndex: 1,
        isBuiltIn: true
    )

    static let message = Mode(
        id: messageID,
        name: "Message",
        icon: "bubble.left",
        colorHex: "#30D158",
        description: "Casual chat tone, contractions kept",
        instructions: "Keep it casual and short. Fix grammar lightly but preserve tone. Emoji allowed.",
        readsSelectedText: false,
        readsClipboard: false,
        autoActivationRules: [],
        shortcutIndex: 2,
        isBuiltIn: true
    )

    static let note = Mode(
        id: noteID,
        name: "Note",
        icon: "note.text",
        colorHex: "#FF9F0A",
        description: "Structured notes with bullets",
        instructions: "Turn the transcription into a structured note. Use a short title and bullet points.",
        readsSelectedText: false,
        readsClipboard: false,
        autoActivationRules: [],
        shortcutIndex: 3,
        isBuiltIn: true
    )

    static let meeting = Mode(
        id: meetingID,
        name: "Meeting",
        icon: "person.2",
        colorHex: "#BF5AF2",
        description: "Action items with owners and due dates",
        instructions: "Extract action items. Assign owners and due dates where mentioned. Format as a list.",
        readsSelectedText: true,
        readsClipboard: false,
        autoActivationRules: [],
        shortcutIndex: 4,
        isBuiltIn: true
    )

    /// Identity transform — never sent to an LLM (§7).
    static let voiceNote = Mode(
        id: voiceNoteID,
        name: voiceNoteName,
        icon: "mic",
        colorHex: "#64D2FF",
        description: "Pure transcript, no AI processing",
        instructions: "",
        readsSelectedText: false,
        readsClipboard: false,
        autoActivationRules: [],
        shortcutIndex: 5,
        isBuiltIn: true
    )

    static let writeForMe = Mode(
        id: writeForMeID,
        name: "Write for me",
        icon: "pencil.line",
        colorHex: "#FF453A",
        description: "Drafts text from a short prompt",
        instructions: "Write the text for me based on my prompt. Match the requested tone and length.",
        readsSelectedText: false,
        readsClipboard: false,
        autoActivationRules: [],
        shortcutIndex: 6,
        isBuiltIn: true
    )

    /// Popover-switcher-only per §6.2; context flags on ("Super" badge).
    static let superMode = Mode(
        id: superModeID,
        name: "Super Mode",
        icon: "sparkles",
        colorHex: "#BF5AF2",
        description: "Acts on the current app context",
        instructions: "Act on the user's dictated request. When context from the current app is provided, use it to ground the answer. Be concise. Output only the result text.",
        readsSelectedText: true,
        readsClipboard: true,
        autoActivationRules: [],
        shortcutIndex: 7,
        isBuiltIn: true
    )

    /// Library order follows the §6.2 seed (⌘1–⌘6) with Super Mode last (⌘7).
    static let all: [Mode] = [email, message, note, meeting, voiceNote, writeForMe, superMode]

    /// §6.2 seeded customs. Slack Update holds no ⌘ (the prototype's ⌘7
    /// collides with Super Mode's — the one shortcutIndex space can't hold both).
    static let seededCustoms: [Mode] = [
        Mode(
            id: slackUpdateID,
            name: "Slack Update",
            icon: "number",
            colorHex: "#30D158",
            description: "Casual standup format for team channels",
            instructions: "Format as a casual standup update: Yesterday / Today / Blockers. Keep it breezy, use channel-friendly shorthand.",
            readsSelectedText: false,
            readsClipboard: false,
            autoActivationRules: [],
            shortcutIndex: nil,
            isBuiltIn: false
        ),
        Mode(
            id: supportReplyID,
            name: "Support Reply",
            icon: "lifebuoy",
            colorHex: "#BF5AF2",
            description: "Empathetic tone, includes ticket macro",
            instructions: "Rewrite as an empathetic support reply. Acknowledge the issue, give the fix, and append the ticket macro.",
            readsSelectedText: true,
            readsClipboard: true,
            autoActivationRules: [],
            shortcutIndex: 8,
            isBuiltIn: false
        ),
    ]

    /// §6.2 editor constants.
    static let colorSwatches = ["#0A84FF", "#30D158", "#FF9F0A", "#BF5AF2", "#64D2FF", "#FF453A"]
    static let iconPickerOptions = ["envelope", "bubble.left", "number", "note.text", "person.2", "mic", "pencil.line", "sparkles"]
    static let ruleApps = ["Mail", "Slack", "Notes", "Safari"]
    static let instructionsPlaceholder = "Rewrite the transcription as a professional email. Keep it under 120 words. Sign off with my name."
    /// §6.2 generic live-preview sample for brand-new modes.
    static let newModeSample = "um okay so the deploy is green and the metrics look fine, I'll send the summary right after lunch"
}
