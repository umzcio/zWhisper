import Foundation
import Testing
@testable import zWhisper

@Suite("PersistenceStore")
struct PersistenceStoreTests {
    private func makeStore() throws -> (PersistenceStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        return (PersistenceStore(directory: dir), dir)
    }

    @Test("load returns nil for a missing file (first launch)")
    func loadMissingFile() async throws {
        let (store, _) = try makeStore()
        let loaded = try await store.load([HistoryEntry].self, from: "history.json")
        #expect(loaded == nil)
    }

    @Test("save → load round-trips a history entry")
    func historyRoundTrip() async throws {
        let (store, _) = try makeStore()
        let entry = HistoryEntry(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 38.2,
            modeID: UUID(),
            rawTranscript: "um so the raw transcript",
            processedText: "The processed transcript.",
            audioPath: "audio/\(UUID().uuidString).m4a",
            segments: [TranscriptSegment(text: "The processed transcript.", start: 0, end: 2.1)],
            undoStack: [ProcessedVersion(modeID: UUID(), text: "Earlier version.", createdAt: Date())],
            targetApp: "com.apple.TextEdit"
        )
        try await store.save([entry], to: "history.json")
        let loaded = try await store.load([HistoryEntry].self, from: "history.json")
        #expect(loaded == [entry])
    }

    @Test("save → load round-trips settings and vocabulary")
    func settingsAndVocabularyRoundTrip() async throws {
        let (store, _) = try makeStore()
        var settings = SettingsStore()
        settings.theme = .light
        settings.activeDuration = nil
        try await store.save(settings, to: "settings.json")
        #expect(try await store.load(SettingsStore.self, from: "settings.json") == settings)

        let vocab = VocabularyStore(
            customWords: [Word(id: UUID(), text: "zWhisper", useCount: 12, lastUsedAt: Date())],
            replacements: [Replacement(id: UUID(), trigger: "my email", replacement: "alex@zwhisper.app")]
        )
        try await store.save(vocab, to: "vocabulary.json")
        #expect(try await store.load(VocabularyStore.self, from: "vocabulary.json") == vocab)
    }

    @Test("repeated saves overwrite (atomic write leaves no partial state)")
    func overwrite() async throws {
        let (store, _) = try makeStore()
        try await store.save(["first"], to: "w.json")
        try await store.save(["second"], to: "w.json")
        #expect(try await store.load([String].self, from: "w.json") == ["second"])
    }

    @Test("debounced save coalesces bursts and flush persists the latest value")
    func debounce() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        let store = PersistenceStore(directory: dir, debounceInterval: .milliseconds(50))

        await store.saveDebounced(["v1"], to: "d.json")
        await store.saveDebounced(["v2"], to: "d.json")
        await store.saveDebounced(["v3"], to: "d.json")

        // Not yet written — the debounce interval has not elapsed.
        #expect(try await store.load([String].self, from: "d.json") == nil)

        await store.flush()
        #expect(try await store.load([String].self, from: "d.json") == ["v3"])
    }

    @Test("files land in the zWhisper Application Support directory by default")
    func defaultDirectory() async {
        let store = PersistenceStore()
        let directory = await store.directory
        #expect(directory.lastPathComponent == "zWhisper")
        #expect(directory.path(percentEncoded: false).contains("Library/Application Support"))
    }
}
