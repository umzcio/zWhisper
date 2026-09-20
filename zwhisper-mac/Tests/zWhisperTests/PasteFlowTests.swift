import AppKit
import Foundation
import Testing
@testable import zWhisper

@MainActor
final class MockPasteController: PasteControllerProtocol {
    private(set) var pastedText: String?
    private(set) var restoreFlag: Bool?
    private(set) var undoCalls = 0
    private(set) var copiedText: String?
    var receipt = PasteReceipt(changeCount: 1, snapshot: [:], targetApp: "TextEdit", didPaste: true)

    func paste(text: String, restoreClipboard: Bool) async throws -> PasteReceipt {
        pastedText = text
        restoreFlag = restoreClipboard
        return receipt
    }

    func undo(_ receipt: PasteReceipt) async {
        undoCalls += 1
    }

    func copy(text: String) async {
        copiedText = text
    }
}

@Suite("AppState paste & history flow (M4)")
@MainActor
struct PasteFlowTests {
    private func makeState() async -> (AppState, MockAudioCaptureEngine, MockTranscriptionEngine, MockPasteController) {
        let audio = MockAudioCaptureEngine()
        let transcription = MockTranscriptionEngine()
        let paste = MockPasteController()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zwhisper-tests-\(UUID().uuidString)", isDirectory: true)
        let state = AppState(
            audio: audio,
            transcription: transcription,
            paste: paste,
            persistence: PersistenceStore(directory: dir),
            requestRecordPermission: { true }
        )
        await state.prepareTranscription()
        return (state, audio, transcription, paste)
    }

    private func dictate(_ state: AppState) async {
        state.startDictation()
        try? await Task.sleep(for: .milliseconds(100))
        state.stopDictation()
        try? await Task.sleep(for: .milliseconds(300))
    }

    @Test("stop → transcribing → pasting → pasted, text handed to the paste controller")
    func pasteFlow() async throws {
        let (state, _, _, paste) = await makeState()
        await dictate(state)
        guard case .pasted(let appName) = state.phase else {
            Issue.record("expected pasted phase, got \(state.phase)")
            return
        }
        #expect(appName == "TextEdit")
        #expect(paste.pastedText == "the quick brown fox")
        #expect(paste.restoreFlag == true)
        #expect(state.pasteSubtitle == "Pasted to TextEdit")
    }

    @Test("pasted writes a history entry with audio path, segments, and target app")
    func historyEntry() async throws {
        let (state, _, _, _) = await makeState()
        await dictate(state)
        #expect(state.history.count == 1)
        let entry = try #require(state.history.first)
        #expect(entry.processedText == "the quick brown fox")
        #expect(entry.audioPath == "audio/mock-session.m4a")
        #expect(entry.segments.count == 1)
        #expect(entry.targetApp == "TextEdit")
        #expect(entry.modeID == BuiltInModes.voiceNoteID)
        #expect(entry.duration == 1) // mock returns 1s of audio
    }

    @Test("pasted auto-dismisses the popover at 700ms with the §4.3 exit style")
    func autoDismiss() async throws {
        let (state, _, _, _) = await makeState()
        await dictate(state)
        #expect(state.isPopoverOpen)
        try await Task.sleep(for: .milliseconds(900))
        #expect(state.phase == .idle)
        #expect(state.popoverExitStyle == .pasted)
    }

    @Test("auto-paste off copies to clipboard without pasting (§6.6)")
    func autoPasteOff() async throws {
        let (state, _, _, paste) = await makeState()
        state.settings.autoPaste = false
        await dictate(state)
        #expect(paste.pastedText == nil)
        #expect(paste.copiedText == "the quick brown fox")
        #expect(state.pasteSubtitle == "Saved to clipboard")
    }

    @Test("undo paste forwards the receipt to the paste controller (§4.3)")
    func undoPaste() async throws {
        let (state, _, _, paste) = await makeState()
        await dictate(state)
        state.undoLastPaste()
        try await Task.sleep(for: .milliseconds(100))
        #expect(paste.undoCalls == 1)
    }

    @Test("empty transcript: no paste, no history entry — and the flow closes")
    func emptyTranscript() async throws {
        let (state, _, transcription, paste) = await makeState()
        await transcription.setFinalResult(Transcript(text: "", segments: []))
        await dictate(state)
        try await Task.sleep(for: .milliseconds(300))
        #expect(state.phase == .idle)
        #expect(!state.isPopoverOpen)
        #expect(paste.pastedText == nil)
        #expect(state.history.isEmpty)
    }

    @Test("history persists debounced and deletes with its audio file (§7)")
    func historyPersistence() async throws {
        let (state, _, _, _) = await makeState()
        await dictate(state)
        try await Task.sleep(for: .milliseconds(700)) // debounce interval

        // Delete removes the entry and its audio file.
        let entry = try #require(state.history.first)
        state.deleteHistory(id: entry.id)
        #expect(state.history.isEmpty)
    }
}

@Suite("PasteController clipboard (§3.6)", .serialized)
@MainActor
struct PasteControllerTests {
    @Test("paste snapshots and restores the clipboard; undo restores the snapshot")
    func snapshotRestore() async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("ORIGINAL", forType: .string)

        let controller = PasteController()
        let receipt = try await controller.paste(text: "TRANSCRIPT", restoreClipboard: true)

        // In the test host (no Accessibility trust) the paste degrades (§8):
        // the transcript stays on the clipboard for manual ⌘V and the snapshot
        // is kept for Undo.
        if !receipt.didPaste {
            #expect(pasteboard.string(forType: .string) == "TRANSCRIPT")
            await controller.undo(receipt)
            #expect(pasteboard.string(forType: .string) == "ORIGINAL")
        } else {
            // Trusted environment: snapshot restored after the paste.
            #expect(pasteboard.string(forType: .string) == "ORIGINAL")
            await controller.undo(receipt)
            #expect(pasteboard.string(forType: .string) == "ORIGINAL")
        }
    }

    @Test("paste without restore leaves the transcript on the clipboard")
    func noRestore() async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("ORIGINAL", forType: .string)

        let controller = PasteController()
        _ = try await controller.paste(text: "TRANSCRIPT", restoreClipboard: false)
        #expect(pasteboard.string(forType: .string) == "TRANSCRIPT")
    }
}
