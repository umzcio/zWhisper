import AVFAudio
import AppKit
import LaunchAtLogin
import SwiftUI

/// The dictation state machine (architecture §4). M5 covers the full chain:
/// idle → recording → transcribing → processing → pasting → pasted → idle.
enum DictationPhase: Equatable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case processing
    case pasting
    /// Auto-dismisses 700ms after appearing (§4.3).
    case pasted(appName: String)
}

/// Speech-model readiness; gates dictation and drives the popover hint.
enum ModelStatus: Equatable {
    case notStarted
    case downloading(Double)
    case ready
    case failed
}

/// Tracks download throughput across Progress callbacks (Models screen MB/s).
private final class DownloadSpeedTracker: @unchecked Sendable {
    private var lastBytes: Int64 = 0
    private var lastTime = ContinuousClock.now

    /// Returns bytes/second since the previous sample (0 until 200ms elapse).
    func sample(bytes: Int64) -> Double {
        let now = ContinuousClock.now
        let elapsed = now - lastTime
        guard elapsed > .milliseconds(200), bytes > lastBytes else { return 0 }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let speed = Double(bytes - lastBytes) / seconds
        lastBytes = bytes
        lastTime = now
        return speed
    }
}

/// Which §4 exit animation the popover plays on dismiss.
enum PopoverExitStyle {
    /// Reverse of summon: scale→0.85, y→−8 (§3.1).
    case standard
    /// §4.3: scale→0.9, y→−4, fade.
    case pasted
}

/// Single source of truth (architecture §3.1). The only type allowed to mutate
/// `phase`; services publish narrow callbacks into it.
@MainActor @Observable
final class AppState {
    enum PopoverSize {
        case main, mini
    }

    /// SPRING_POP from spec §5.1 (spring 400/28).
    static let springPop = Animation.spring(response: 0.31, dampingFraction: 0.70)
    /// SPRING_DEFAULT from spec §5.1 (spring 400/30) — layout changes on resize.
    static let springDefault = Animation.spring(response: 0.31, dampingFraction: 0.75)

    /// §5.5 reduced motion: springs become 150ms fades.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var popAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : springPop
    }

    // MARK: Popover (M1)

    /// True while the popover is logically open (panel may still be animating).
    private(set) var isPopoverOpen = false
    /// Drives the SPRING_POP entrance/exit in the content view (spec §3.1 summon).
    private(set) var popoverAppeared = false
    private(set) var popoverExitStyle: PopoverExitStyle = .standard
    var popoverSize: PopoverSize = .main
    /// Increment to replay the cancel shake keyframes (spec §3.1 `cancelled`).
    private(set) var cancelShakeTrigger = 0

    weak var popover: PopoverController?
    weak var toast: ToastController?
    weak var switcher: ModeSwitcherController?
    /// Claims/releases the ⌘-digit hotkeys with popover visibility, so
    /// iTerm/Chrome keep their tab shortcuts while the popover is closed.
    var setModeDigitsEnabled: ((Bool) -> Void)?
    /// Claims/releases the bare Esc hotkey with popover visibility — a
    /// permanently-held Esc steals Escape from every app system-wide.
    var setEscapeHotkeyEnabled: ((Bool) -> Void)?

    // MARK: Dictation (M2–M5)

    private(set) var phase: DictationPhase = .idle
    var settings = SettingsStore()
    /// Set when the user triggers dictation without microphone permission (§8).
    private(set) var micDenied = false
    /// Normalized (0…1) input level, updated from the audio tap's RMS stream.
    private(set) var currentLevel: Float = 0
    let waveform = WaveformModel()

    private(set) var modelStatus: ModelStatus = .notStarted
    /// Teleprompter text (§3.1): streaming partial while recording.
    private(set) var partialText = ""
    /// Transcript / processed result shown in the teleprompter.
    private(set) var transcriptText = ""
    private(set) var transcriptionFailed = false
    private(set) var lastTranscript: Transcript?
    /// Subtitle for the pasted caption + result toast (§4.3).
    private(set) var pasteSubtitle = ""

    // MARK: Modes (M5–M6)

    /// Built-in library (§6.2) + customs from modes.json (§7).
    private(set) var modes: [Mode] = BuiltInModes.all
    private var customs: [Mode] = []
    private(set) var activeMode: Mode = BuiltInModes.voiceNote
    /// Mode rewrite as it streams in during `processing` (§4: partials into the teleprompter).
    private(set) var processedText = ""
    /// Apple Intelligence off + no cloud key → actionable failure (§8/§10.4).
    private(set) var modeProcessingFailed = false
    private(set) var failedModeName = ""
    /// Increment to pulse the mode pill on mode change (§3.1, SPRING_MICRO).
    private(set) var modePulseTrigger = 0
    /// True while push-to-talk is physically held (§3.1 caption, §4.1 hold trigger).
    private(set) var holdToTalkActive = false
    /// Context capture for Super-flagged modes (§3.7); lights the §3.1 context dot.
    private(set) var capturedContext: CapturedContext?
    private(set) var contextCaptured = false

    // MARK: Vocabulary (M6)

    private(set) var vocabulary = VocabularyStore.empty

    // MARK: Models (M6)

    private(set) var modelPreferences = ModelPreferences()
    /// Per-variant row state for the §6.4 Models screen (locals only).
    private(set) var modelStates: [String: ModelDownloadStatus] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    // MARK: Management window (M6)

    var managementScreen: ManagementScreen = .history

    // MARK: History (M4)

    private(set) var history: [HistoryEntry] = []

    private let audio: AudioCaptureEngineProtocol
    private let transcription: TranscriptionEngineProtocol
    private(set) var modeProcessor: ModeProcessorProtocol
    private let paste: PasteControllerProtocol
    private let persistence: PersistenceStore
    private let requestRecordPermission: @Sendable () async -> Bool
    private var lastPasteReceipt: PasteReceipt?
    private var lastSessionDuration: TimeInterval = 0
    private var lastAudioPath: String?
    private var levelForwardingTask: Task<Void, Never>?
    private var bufferForwardingTask: Task<Void, Never>?
    private var partialForwardingTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var metering = false

    init(
        audio: AudioCaptureEngineProtocol = AudioCaptureEngine(),
        transcription: TranscriptionEngineProtocol = TranscriptionEngine(),
        modeProcessor: ModeProcessorProtocol = ModeProcessor.makeDefault(),
        paste: PasteControllerProtocol = PasteController(),
        persistence: PersistenceStore = PersistenceStore(),
        requestRecordPermission: @escaping @Sendable () async -> Bool = AppState.requestSystemRecordPermission
    ) {
        self.audio = audio
        self.transcription = transcription
        self.modeProcessor = modeProcessor
        self.paste = paste
        self.persistence = persistence
        self.requestRecordPermission = requestRecordPermission
    }

    static func requestSystemRecordPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        default: return false
        }
    }

    // MARK: Model & vocabulary (M3)

    /// First-launch model download (with progress) + load, then vocabulary (§6.5).
    /// Loads the persisted §6.4 active model when one is set and downloaded.
    func prepareTranscription() async {
        guard case .notStarted = modelStatus else { return }
        modelStatus = .downloading(0)
        do {
            await loadModelPreferences()
            if let activeID = modelPreferences.activeLocalID,
               ModelDownloadManager.isDownloaded(variant: activeID)
            {
                try await transcription.loadModel(at: ModelDownloadManager.modelFolder(forVariant: activeID))
            } else {
                try await transcription.load { [weak self] fraction in
                    Task { @MainActor in self?.modelStatus = .downloading(fraction) }
                }
            }
            modelStatus = .ready
        } catch {
            modelStatus = .failed
        }
        await loadVocabulary()
    }

    func loadVocabulary() async {
        vocabulary = (try? await persistence.load(VocabularyStore.self, from: "vocabulary.json")) ?? .empty
        await transcription.setVocabulary(vocabulary.customWords.map(\.text))
    }

    // MARK: Vocabulary (M6)

    /// §6.5: add returns false on duplicate (input shakes + red ring).
    @discardableResult
    func addVocabularyWord(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !vocabulary.customWords.contains(where: { $0.text.localizedCaseInsensitiveCompare(trimmed) == .orderedSame })
        else { return false }
        vocabulary.customWords.append(Word(id: UUID(), text: trimmed, useCount: 0, lastUsedAt: nil))
        vocabularyDidChange()
        return true
    }

    func removeVocabularyWord(id: UUID) {
        vocabulary.customWords.removeAll { $0.id == id }
        vocabularyDidChange()
    }

    func addReplacement(trigger: String, replacement: String) {
        vocabulary.replacements.append(Replacement(id: UUID(), trigger: trigger, replacement: replacement))
        vocabularyDidChange()
    }

    func updateReplacement(_ replacement: Replacement) {
        guard let index = vocabulary.replacements.firstIndex(where: { $0.id == replacement.id }) else { return }
        vocabulary.replacements[index] = replacement
        vocabularyDidChange()
    }

    func removeReplacement(id: UUID) {
        vocabulary.replacements.removeAll { $0.id == id }
        vocabularyDidChange()
    }

    /// §6.5/§7: useCount/lastUsedAt increment when a word appears in a final transcript.
    private func noteVocabularyUsage(in text: String) {
        var changed = false
        for index in vocabulary.customWords.indices {
            let word = vocabulary.customWords[index]
            if text.localizedCaseInsensitiveContains(word.text) {
                vocabulary.customWords[index].useCount += 1
                vocabulary.customWords[index].lastUsedAt = .now
                changed = true
            }
        }
        if changed {
            vocabularyDidChange()
        }
    }

    private func vocabularyDidChange() {
        Task { await persistence.saveDebounced(vocabulary, to: "vocabulary.json") }
        let words = vocabulary.customWords.map(\.text)
        Task { await transcription.setVocabulary(words) }
    }

    // MARK: Models (M6)

    func loadModelPreferences() async {
        modelPreferences = (try? await persistence.load(ModelPreferences.self, from: "models.json")) ?? ModelPreferences()
        for entry in ModelCatalogEntry.locals {
            if modelPreferences.activeLocalID == entry.id, ModelDownloadManager.isDownloaded(variant: entry.id) {
                modelStates[entry.id] = .active
            } else if ModelDownloadManager.isDownloaded(variant: entry.id) {
                modelStates[entry.id] = .downloaded
            } else {
                modelStates[entry.id] = .none
            }
        }
    }

    private func saveModelPreferences() {
        Task { await persistence.saveDebounced(modelPreferences, to: "models.json") }
    }

    func toggleModelFavorite(id: String) {
        if modelPreferences.favoriteIDs.contains(id) {
            modelPreferences.favoriteIDs.removeAll { $0 == id }
        } else {
            modelPreferences.favoriteIDs.append(id)
        }
        saveModelPreferences()
    }

    /// §6.4: max 2 concurrent downloads; further taps queue.
    func downloadModel(_ id: String) {
        guard modelStates[id] == .none || modelStates[id] == nil else { return }
        if downloadTasks.count >= 2 {
            modelStates[id] = .queued
            return
        }
        startModelDownload(id)
    }

    private func startModelDownload(_ id: String) {
        modelStates[id] = .downloading(progress: 0, bytesPerSecond: 0)
        let tracker = DownloadSpeedTracker()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await ModelDownloadManager().download(variant: id) { progress in
                    let speed = tracker.sample(bytes: progress.completedUnitCount)
                    Task { @MainActor in
                        if case .downloading = self.modelStates[id] {
                            self.modelStates[id] = .downloading(progress: progress.fractionCompleted, bytesPerSecond: speed)
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                self.modelStates[id] = .downloaded
            } catch {
                if !Task.isCancelled {
                    Self.logToStderr("model download failed (\(id)): \(error)")
                }
                self.modelStates[id] = .none
            }
            self.downloadTasks.removeValue(forKey: id)
            self.startNextQueuedDownload()
        }
        downloadTasks[id] = task
    }

    private func startNextQueuedDownload() {
        guard downloadTasks.count < 2,
              let next = modelStates.first(where: { $0.value == .queued })?.key
        else { return }
        startModelDownload(next)
    }

    func cancelModelDownload(_ id: String) {
        if modelStates[id] == .queued {
            modelStates[id] = .none
            return
        }
        downloadTasks[id]?.cancel()
        downloadTasks.removeValue(forKey: id)
        modelStates[id] = .none
        startNextQueuedDownload()
    }

    func deleteModelDownload(_ id: String) {
        try? ModelDownloadManager.delete(variant: id)
        if modelStates[id] == .active {
            modelStates[id] = .none
            modelPreferences.activeLocalID = nil
            saveModelPreferences()
        } else {
            modelStates[id] = .none
        }
    }

    /// §6.4 Set Active: reloads the transcription engine on the new variant.
    func setActiveModel(_ id: String) {
        guard ModelDownloadManager.isDownloaded(variant: id) else { return }
        Task { @MainActor in
            do {
                try await transcription.loadModel(at: ModelDownloadManager.modelFolder(forVariant: id))
                for key in modelStates.keys where modelStates[key] == .active {
                    modelStates[key] = .downloaded
                }
                modelStates[id] = .active
                modelPreferences.activeLocalID = id
                saveModelPreferences()
                Self.logToStderr("active model: \(id)")
            } catch {
                Self.logToStderr("setActiveModel failed (\(id)): \(error)")
            }
        }
    }

    /// §6.4 ApiKeyPopover: key → Keychain, backends rebuilt (§6).
    func saveCloudAPIKey(_ key: String, for account: String) {
        KeychainStore.setAPIKey(key, for: account)
        modeProcessor = ModeProcessor.makeDefault()
    }

    func cloudAPIKeyAccount(for provider: String) -> String {
        provider.lowercased()
    }

    func hasCloudAPIKey(for account: String) -> Bool {
        KeychainStore.apiKey(for: account) != nil
    }

    // MARK: History (M4)

    func loadHistory() async {
        history = (try? await persistence.load([HistoryEntry].self, from: "history.json")) ?? []
    }

    /// Newest first, soft-capped at 1000 entries (§7).
    func appendHistory(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > 1000 {
            history.removeLast(history.count - 1000)
        }
        Task { await persistence.saveDebounced(history, to: "history.json") }
    }

    private func replaceHistory(_ entry: HistoryEntry) {
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        history[index] = entry
        Task { await persistence.saveDebounced(history, to: "history.json") }
    }

    func deleteHistory(id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        let entry = history.remove(at: index)
        if let path = entry.audioPath {
            Task { await persistence.deleteFile(path) }
        }
        Task { await persistence.saveDebounced(history, to: "history.json") }
    }

    func audioURL(for entry: HistoryEntry) -> URL? {
        guard let path = entry.audioPath else { return nil }
        return persistence.directory.appendingPathComponent(path)
    }

    // MARK: Modes (M5–M6)

    func mode(for id: UUID) -> Mode {
        modes.first { $0.id == id } ?? BuiltInModes.voiceNote
    }

    func loadModes() async {
        // First launch seeds the §6.2 customs (Slack Update, Support Reply).
        customs = (try? await persistence.load([Mode].self, from: "modes.json")) ?? BuiltInModes.seededCustoms
        modes = BuiltInModes.all + customs
    }

    private func saveModes() {
        Task { await persistence.saveDebounced(customs, to: "modes.json") }
    }

    /// §6.2 editor Save. New modes get the next free ⌘ index (prototype `nextShortcut`).
    @discardableResult
    func addCustomMode(_ mode: Mode) -> Mode {
        var mode = mode
        if mode.shortcutIndex == nil {
            mode.shortcutIndex = nextFreeShortcutIndex()
        }
        customs.append(mode)
        modes = BuiltInModes.all + customs
        saveModes()
        return mode
    }

    func updateCustomMode(_ mode: Mode) {
        guard let index = customs.firstIndex(where: { $0.id == mode.id }) else { return }
        customs[index] = mode
        modes = BuiltInModes.all + customs
        if activeMode.id == mode.id {
            activeMode = mode
        }
        saveModes()
    }

    /// §6.2 delete alert: custom modes only (built-ins can't be deleted).
    func deleteCustomMode(id: UUID) {
        customs.removeAll { $0.id == id }
        modes = BuiltInModes.all + customs
        if activeMode.id == id {
            activeMode = BuiltInModes.voiceNote
        }
        saveModes()
    }

    /// §6.2 ⋯ menu Duplicate.
    @discardableResult
    func duplicateMode(_ mode: Mode) -> Mode {
        var copy = mode
        copy = Mode(
            id: UUID(),
            name: mode.name + " copy",
            icon: mode.icon,
            colorHex: mode.colorHex,
            description: mode.description,
            instructions: mode.instructions,
            readsSelectedText: mode.readsSelectedText,
            readsClipboard: mode.readsClipboard,
            autoActivationRules: mode.autoActivationRules,
            shortcutIndex: nil,
            isBuiltIn: false
        )
        return addCustomMode(copy)
    }

    func nextFreeShortcutIndex() -> Int? {
        (1 ... 9).first { index in !modes.contains { $0.shortcutIndex == index } }
    }

    /// §6.2 live preview "Sample": runs the mode over the generic sample.
    func previewMode(_ mode: Mode) -> AsyncThrowingStream<String, Error> {
        modeProcessor.process(raw: BuiltInModes.newModeSample, mode: mode, context: nil)
    }

    /// §6.2 auto-activation (app-level v1): first mode with a rule matching the
    /// frontmost app's display name. Pure — unit-tested without NSWorkspace.
    func modeMatchingRules(frontmostApp: String) -> Mode? {
        modes.first { mode in
            mode.autoActivationRules.contains { $0.appName == frontmostApp }
        }
    }

    /// Live mode switch (§4.2 ⌘1–7): updates `activeMode` only — transcription
    /// is mode-agnostic, nothing restarts; processing uses the mode at stop time.
    func setActiveMode(_ mode: Mode) {
        guard mode.id != activeMode.id else { return }
        activeMode = mode
        modePulseTrigger += 1
        switcher?.dismiss()
    }

    /// Mode pill tap → the §3.4 switcher panel below the pill.
    func toggleSwitcher() {
        guard let popover, let switcher else { return }
        switcher.toggle(below: popover.modePillScreenRect())
    }

    func switchMode(shortcutIndex: Int) {
        Self.logToStderr("switchMode ⌘\(shortcutIndex)")
        guard let mode = modes.first(where: { $0.shortcutIndex == shortcutIndex }) else { return }
        setActiveMode(mode)
    }

    /// ⌥⇧K cycle (§3.5) and toast Reprocess advance (§4.3), in ⌘-index order.
    func nextModeInCycle(after mode: Mode) -> Mode {
        let ordered = modes.sorted { ($0.shortcutIndex ?? 99) < ($1.shortcutIndex ?? 99) }
        guard let index = ordered.firstIndex(where: { $0.id == mode.id }) else {
            return ordered.first ?? BuiltInModes.voiceNote
        }
        return ordered[(index + 1) % ordered.count]
    }

    func cycleMode() {
        setActiveMode(nextModeInCycle(after: activeMode))
    }

    /// §4.3 Reprocess (from toast): restore the pre-paste clipboard, advance to
    /// the next mode in cycle order, reprocess the same utterance, re-paste.
    /// Valid from `pasted` (toast is up) and `idle` (toast outlives the popover).
    func reprocess() {
        guard let transcript = lastTranscript, let receipt = lastPasteReceipt else { return }
        switch phase {
        case .idle, .pasted: break
        default: return
        }
        setActiveMode(nextModeInCycle(after: activeMode))
        toast?.dismiss()
        summonPopover()
        transcriptionTask = Task { @MainActor in
            await paste.undo(receipt)
            await processAndPaste(transcript, reprocess: true)
        }
    }

    // MARK: Dictation actions (architecture §4 triggers)

    /// Spec §4.1: ⌥⇧Space toggle — idle starts recording, recording stops.
    func toggleDictation() {
        switch phase {
        case .idle: startDictation()
        case .recording: stopDictation()
        case .transcribing, .processing, .pasting, .pasted: break
        }
    }

    /// §4.1 push-to-talk: key down (not repeat, no modifiers) starts; key up
    /// stops + pastes. Right ⌘ is the default hold key.
    func startPushToTalk() {
        guard case .idle = phase, !holdToTalkActive else { return }
        holdToTalkActive = true
        startDictation()
    }

    func stopPushToTalk() {
        guard holdToTalkActive else { return }
        holdToTalkActive = false
        if case .recording = phase {
            stopDictation()
        }
    }

    func startDictation() {
        guard case .idle = phase else { return }
        Task { @MainActor in
            guard await requestRecordPermission() else {
                micDenied = true
                summonPopover()
                return
            }
            micDenied = false
            guard modelStatus == .ready else {
                summonPopover()
                return
            }
            // §6.2 auto-activation rules (app-level in v1; Safari domain inert):
            // a mode whose rule matches the frontmost app becomes active.
            let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            if let matched = modeMatchingRules(frontmostApp: frontmost), matched.id != activeMode.id {
                setActiveMode(matched)
            }
            do {
                try await audio.start()
            } catch {
                return
            }
            phase = .recording(startedAt: .now)
            ZWSoundEffects.play(.recordStart, style: settings.soundEffectsStyle)
            partialText = ""
            transcriptText = ""
            processedText = ""
            transcriptionFailed = false
            modeProcessingFailed = false
            contextCaptured = false
            capturedContext = nil
            summonPopover()
            waveform.beginLive()
            startLevelForwarding()
            startBufferForwarding()
            startPartialForwarding()
            startContextCapture()
            scheduleAutoStop()
        }
    }

    /// §3.7: context capture runs in parallel with recording start against the
    /// 600ms §7 CONTEXT_MS budget; the dot lights when capture lands.
    private func startContextCapture() {
        let mode = activeMode
        guard mode.readsSelectedText || mode.readsClipboard else { return }
        Task { @MainActor in
            let context = await ContextCapture.capture(
                readSelectedText: mode.readsSelectedText,
                readClipboard: mode.readsClipboard
            )
            guard case .recording = phase else { return }
            capturedContext = context
            contextCaptured = context != nil
        }
    }

    /// §4: stop → settle → transcribing → (processing) → pasting → pasted.
    func stopDictation() {
        guard case .recording = phase else { return }
        autoStopTask?.cancel()
        transcriptionTask = Task { @MainActor in
            let sessionAudio = await audio.stop()
            ZWSoundEffects.play(.recordStop, style: settings.soundEffectsStyle)
            lastSessionDuration = Double(sessionAudio.frameLength) / 16_000
            lastAudioPath = await audio.sessionAudioRelativePath
            phase = .transcribing
            waveform.beginSettle(now: .now, barCount: popoverSize == .main ? 48 : 28)
            do {
                let started = ContinuousClock.now
                let transcript = try await transcription.transcribeFinal(sessionAudio)
                let elapsed = ContinuousClock.now - started
                Self.logToStderr("final transcription pass: \(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)ms, \(transcript.text.count) chars")
                guard case .transcribing = phase else { return } // cancelled meanwhile
                lastTranscript = transcript
                transcriptText = transcript.text
                partialText = ""
                noteVocabularyUsage(in: transcript.text)
            } catch {
                guard case .transcribing = phase else { return }
                transcriptionFailed = true
                phase = .idle
                return
            }
            guard let transcript = lastTranscript else {
                phase = .idle
                return
            }
            await processAndPaste(transcript)
        }
    }

    /// §4: Voice Note short-circuits to pasting (§7 identity); other modes
    /// stream the rewrite into the teleprompter (≤700ms to first token, §7).
    private func processAndPaste(_ transcript: Transcript, reprocess: Bool = false) async {
        let mode = activeMode
        guard !mode.isIdentity else {
            await pasteAndFinish(raw: transcript.text, processed: transcript.text, mode: mode, reprocess: reprocess)
            return
        }
        phase = .processing
        processedText = ""
        modeProcessingFailed = false
        let started = ContinuousClock.now
        var loggedFirstToken = false
        do {
            for try await chunk in modeProcessor.process(raw: transcript.text, mode: mode, context: capturedContext) {
                guard case .processing = phase else { return } // cancelled meanwhile
                if !loggedFirstToken {
                    let elapsed = ContinuousClock.now - started
                    Self.logToStderr("processing first token: \(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)ms (\(mode.name))")
                    loggedFirstToken = true
                }
                processedText = chunk
            }
        } catch {
            guard case .processing = phase else { return }
            modeProcessingFailed = true
            failedModeName = mode.name
            phase = .idle
            return
        }
        let processed = processedText.isEmpty ? transcript.text : processedText
        transcriptText = processed
        await pasteAndFinish(raw: transcript.text, processed: processed, mode: mode, reprocess: reprocess)
    }

    /// §4.3 stop → paste sequence: paste at the caret, "Pasted to {app}",
    /// history entry, result toast (6s), popover closes 700ms after pasted.
    private func pasteAndFinish(raw: String, processed: String, mode: Mode, reprocess: Bool) async {
        // Nothing usable came back (silence, hallucination-free empty pass):
        // no paste, no history entry (§4: cancel-like no-op).
        guard !processed.isEmpty else {
            if let path = lastAudioPath {
                Task { await persistence.deleteFile(path) }
            }
            phase = .idle
            return
        }
        phase = .pasting
        var receipt: PasteReceipt?
        if settings.autoPaste {
            receipt = try? await paste.paste(text: processed, restoreClipboard: settings.restoreClipboard)
        } else {
            await paste.copy(text: processed)
        }
        lastPasteReceipt = receipt

        if let receipt, receipt.didPaste {
            pasteSubtitle = receipt.targetApp.isEmpty ? "Pasted" : "Pasted to \(receipt.targetApp)"
        } else if settings.autoPaste, receipt != nil {
            pasteSubtitle = "Press ⌘V to paste" // AX degraded path (§8)
        } else {
            pasteSubtitle = "Saved to clipboard"
        }
        phase = .pasted(appName: receipt?.targetApp ?? "")

        if reprocess, let last = history.first {
            // §6.3 per-entry reprocess history (undo stack).
            var updated = last
            updated.undoStack.append(ProcessedVersion(modeID: last.modeID, text: last.processedText, createdAt: .now))
            updated.modeID = mode.id
            updated.processedText = processed
            replaceHistory(updated)
        } else {
            appendHistory(HistoryEntry(
                id: UUID(),
                createdAt: Date.now,
                duration: lastSessionDuration,
                modeID: mode.id,
                rawTranscript: raw,
                processedText: processed,
                audioPath: lastAudioPath,
                segments: lastTranscript?.segments ?? [],
                undoStack: [],
                targetApp: receipt?.targetApp
            ))
        }

        let words = processed.split(separator: " ").count
        toast?.show(ResultToast(words: words, duration: lastSessionDuration, subtitle: pasteSubtitle)) { [weak self] in
            self?.undoLastPaste()
        } onReprocess: { [weak self] in
            self?.reprocess()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, case .pasted = self.phase else { return }
            self.phase = .idle
            // §6.6 "Always close window after dictation"; the docked indicator
            // always collapses (otherwise Esc/⌘-digits would stay claimed at idle).
            if self.settings.alwaysCloseWindowAfterDictation || self.isDocked {
                self.dismissPopover(style: .pasted)
            }
        }
    }

    /// §4.3 "Undo paste": restores the pre-paste clipboard snapshot.
    func undoLastPaste() {
        guard let receipt = lastPasteReceipt else { return }
        Task { await paste.undo(receipt) }
    }

    /// Esc / ✕ (spec §4.2): discard audio, no paste, shake, close at 420ms.
    /// Esc works in recording, transcribing, and processing alike.
    func cancel() {
        holdToTalkActive = false
        switch phase {
        case .recording:
            autoStopTask?.cancel()
            phase = .idle
            waveform.reset()
            Task { await audio.cancel() }
        case .transcribing, .processing:
            transcriptionTask?.cancel()
            phase = .idle
            partialText = ""
            transcriptText = ""
            processedText = ""
        case .idle, .pasting, .pasted:
            break
        }
        guard isPopoverOpen else { return }
        cancelShakeTrigger += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            self?.dismissPopover()
        }
    }

    /// Status item click (spec §4.1): toggles the popover; while recording it
    /// stops. On summon it auto-starts when Settings → General says so (§6.6).
    func statusItemClicked() {
        switch phase {
        case .recording:
            stopDictation()
        case .transcribing, .processing, .pasting, .pasted:
            break
        case .idle:
            if isPopoverOpen {
                dismissPopover()
            } else {
                summonPopover()
                if settings.startRecordingOnStatusItemClick {
                    startDictation()
                }
            }
        }
    }

    /// Settings → Sound input meter (§6.6): levels-only capture while the pane is visible.
    func startMetering() {
        Task { @MainActor in
            guard await requestRecordPermission() else {
                micDenied = true
                return
            }
            guard !metering, case .idle = phase else { return }
            metering = true
            try? await audio.startMetering()
            startLevelForwarding()
        }
    }

    func stopMetering() {
        guard metering else { return }
        metering = false
        Task { await audio.stopMetering() }
        currentLevel = 0
    }

    // MARK: Settings persistence (architecture §7)

    func loadSettings() async {
        if let loaded = try? await persistence.load(SettingsStore.self, from: "settings.json") {
            settings = loaded
        }
        applyAudioSettings()
        applyGeneralSettings()
    }

    func settingsDidChange() {
        applyAudioSettings()
        applyGeneralSettings()
        Task { await persistence.saveDebounced(settings, to: "settings.json") }
    }

    /// §6.6 General pane: theme override, Dock visibility, launch at login, language.
    private func applyGeneralSettings() {
        switch settings.theme {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        }
        if NSApp.activationPolicy() != (settings.showInDock ? .regular : .accessory) {
            NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        }
        if LaunchAtLogin.isEnabled != settings.launchAtLogin {
            LaunchAtLogin.isEnabled = settings.launchAtLogin
        }
        let code = settings.language == "auto" ? nil : settings.language
        let translate = settings.translateToEnglish
        Task { await transcription.setLanguage(code, translateToEnglish: translate) }

        // Docked indicator placement (SuperWhisper-style bottom-right pill).
        popover?.placement = settings.popoverPlacement
        if isDocked {
            if popoverSize != .mini {
                popoverSize = .mini
                popover?.animateFrame(to: .mini)
            }
            popover?.presentPersistent()
            popoverAppeared = true
        } else if !isPopoverOpen {
            popoverAppeared = false
            popover?.dismissAfterExitAnimation()
        }
    }

    /// Docked indicator mode: a persistent mini pill at the bottom-right.
    var isDocked: Bool {
        settings.popoverPlacement == .bottomRight
    }

    private func applyAudioSettings() {
        let normalization = settings.dynamicNormalization
        let removal = settings.silenceRemoval
        let aggressiveness = settings.silenceAggressiveness
        Task {
            await audio.setNormalizationEnabled(normalization)
            await audio.setSilenceRemoval(enabled: removal, aggressiveness: aggressiveness)
        }
    }

    // MARK: Popover actions (M1)

    func togglePopover() {
        isPopoverOpen ? dismissPopover() : summonPopover()
    }

    func summonPopover() {
        guard !isPopoverOpen else { return }
        isPopoverOpen = true
        popoverExitStyle = .standard
        setModeDigitsEnabled?(true)
        setEscapeHotkeyEnabled?(true)
        popover?.present()
        // Defer one tick so the hidden state renders before the entrance animates.
        Task { @MainActor in
            withAnimation(Self.popAnimation) { self.popoverAppeared = true }
        }
    }

    func dismissPopover(style: PopoverExitStyle = .standard) {
        guard isPopoverOpen else { return }
        isPopoverOpen = false
        popoverExitStyle = style
        setModeDigitsEnabled?(false)
        setEscapeHotkeyEnabled?(false)
        if isDocked {
            // Docked indicator: collapse to the idle mini pill, never hide.
            if popoverSize != .mini {
                popoverSize = .mini
                popover?.animateFrame(to: .mini)
            }
            return
        }
        withAnimation(Self.popAnimation) { popoverAppeared = false }
        popover?.dismissAfterExitAnimation()
    }

    /// Spec §3.1: double-click or the chevron toggle switches Main ↔ Mini.
    func togglePopoverSize() {
        popoverSize = popoverSize == .main ? .mini : .main
        popover?.animateFrame(to: popoverSize)
    }

    /// §3.5 "Dictation" sidebar row: close the management window, summon the popover.
    func dismissManagementWindow() {
        NSApp.windows.first(where: { $0.title == "zWhisper" })?.close()
        summonPopover()
    }

    /// Flushes debounced persistence writes (app termination).
    func flushPersistence() async {
        await persistence.flush()
    }

    // MARK: Internals

    static func logToStderr(_ message: String) {
        FileHandle.standardError.write(Data("[zWhisper] \(message)\n".utf8))
    }

    private func startLevelForwarding() {
        guard levelForwardingTask == nil else { return }
        levelForwardingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rms in self.audio.levels {
                self.currentLevel = Self.normalize(rms)
            }
        }
    }

    /// Voiced 16kHz buffers → the transcription streaming window (§5).
    private func startBufferForwarding() {
        guard bufferForwardingTask == nil else { return }
        bufferForwardingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await buffer in self.audio.buffers {
                await self.transcription.feed(buffer)
            }
        }
    }

    private func startPartialForwarding() {
        guard partialForwardingTask == nil else { return }
        partialForwardingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await partial in self.transcription.partials {
                if case .recording = self.phase {
                    self.partialText = partial
                }
            }
        }
    }

    /// RMS → 0…1 display level over a −55dB…−12dB window (§3.2 amplitude feed).
    static func normalize(_ rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-6))
        return min(1, max(0, (db + 55) / 43))
    }

    /// §6.6 "Active duration" cap: auto-stop as if stop() was pressed (architecture §5).
    private func scheduleAutoStop() {
        autoStopTask?.cancel()
        guard let cap = settings.activeDuration else { return }
        autoStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(cap))
            guard !Task.isCancelled else { return }
            self?.stopDictation()
        }
    }
}
