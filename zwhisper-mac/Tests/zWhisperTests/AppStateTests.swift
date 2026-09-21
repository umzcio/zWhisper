import AppKit
import Foundation
import Testing
@testable import zWhisper

@Suite("AppState popover (M1)")
@MainActor
struct AppStateTests {
    @Test("summon/dismiss toggles open state and plays the entrance")
    func summonDismiss() async throws {
        let state = AppState()
        #expect(!state.isPopoverOpen)

        state.summonPopover()
        #expect(state.isPopoverOpen)
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.popoverAppeared)

        state.dismissPopover()
        #expect(!state.isPopoverOpen)
        #expect(!state.popoverAppeared)
    }

    @Test("toggle flips between summon and dismiss")
    func toggle() {
        let state = AppState()
        state.togglePopover()
        #expect(state.isPopoverOpen)
        state.togglePopover()
        #expect(!state.isPopoverOpen)
    }

    @Test("Esc cancel shakes and closes at 420ms; ignored when closed")
    func cancel() async throws {
        let state = AppState()
        state.cancel()
        #expect(state.cancelShakeTrigger == 0)

        state.summonPopover()
        state.cancel()
        #expect(state.cancelShakeTrigger == 1)
        #expect(state.isPopoverOpen)

        try await Task.sleep(for: .milliseconds(600))
        #expect(!state.isPopoverOpen)
    }

    @Test("size toggle flips Main ↔ Mini")
    func sizeToggle() {
        let state = AppState()
        #expect(state.popoverSize == .main)
        state.togglePopoverSize()
        #expect(state.popoverSize == .mini)
        state.togglePopoverSize()
        #expect(state.popoverSize == .main)
    }

    @Test("⌘-digit hotkeys are claimed only while the popover is open")
    func digitHotkeyGating() {
        let state = AppState()
        var calls: [Bool] = []
        state.setModeDigitsEnabled = { calls.append($0) }
        state.summonPopover()
        #expect(calls == [true])
        state.dismissPopover()
        #expect(calls == [true, false])
    }

    @Test("docked indicator: dismiss collapses instead of hiding")
    func dockedCollapse() {
        let state = AppState()
        state.settings.popoverPlacement = .bottomRight
        state.summonPopover()
        #expect(state.isPopoverOpen)
        state.dismissPopover()
        #expect(!state.isPopoverOpen)
        #expect(state.isDocked)
    }

    @Test("cancel shortcut stores and round-trips; default is esc")
    func cancelShortcutStorage() {
        #expect(CancelShortcut.current == .escape)
        let custom = CancelShortcut(keyCode: 40, modifiers: Int(NSEvent.ModifierFlags.shift.union(.option).rawValue))
        CancelShortcut.store(custom)
        #expect(CancelShortcut.current == custom)
        UserDefaults.standard.removeObject(forKey: "zw.cancelShortcut")
        #expect(CancelShortcut.current == .escape)
    }

    @Test("history trim past 1000 entries deletes the trimmed sessions' audio files")
    func historyTrimDeletesAudio() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("audio", isDirectory: true),
            withIntermediateDirectories: true
        )
        let state = AppState(
            audio: MockAudioCaptureEngine(),
            transcription: MockTranscriptionEngine(),
            paste: MockPasteController(),
            persistence: PersistenceStore(directory: dir),
            requestRecordPermission: { true }
        )
        func makeEntry(_ i: Int) -> HistoryEntry {
            let path = "audio/old-\(i).m4a"
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent(path).path(percentEncoded: false),
                contents: Data()
            )
            return HistoryEntry(
                id: UUID(), createdAt: .now, duration: 1, modeID: UUID(),
                rawTranscript: "t", processedText: "t", audioPath: path,
                segments: [], undoStack: [], targetApp: nil
            )
        }
        for i in 0 ..< 1001 {
            state.appendHistory(makeEntry(i))
        }
        #expect(state.history.count == 1000)
        // Entry 0 (oldest) was trimmed; its file goes. Deletion runs in a Task — poll.
        let trimmed = dir.appendingPathComponent("audio/old-0.m4a").path(percentEncoded: false)
        var gone = false
        for _ in 0 ..< 100 {
            if !FileManager.default.fileExists(atPath: trimmed) { gone = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(gone)
        // A surviving entry's file is untouched.
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("audio/old-1000.m4a").path(percentEncoded: false)
        ))
    }

    @Test("model catalog ids are unique and stable across hardware tiers")
    func catalogIdsUnique() {
        let localIDs = ModelCatalogEntry.locals.map(\.id)
        #expect(Set(localIDs).count == localIDs.count)
        #expect(localIDs == ["tiny", "small", "medium", "large-v3-v20240930_626MB"])
        let allIDs = ModelCatalogEntry.all.map(\.id)
        #expect(Set(allIDs).count == allIDs.count)
    }
}
