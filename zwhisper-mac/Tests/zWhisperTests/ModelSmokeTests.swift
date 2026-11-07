import AVFAudio
import Foundation
import Testing
@testable import zWhisper

/// Downloads and runs the real NVIDIA models. Off by default (≈1.4 GB):
/// TEST_RUNNER_ZW_MODEL_SMOKE=<16 kHz wav> xcodebuild test …
@Suite("Model smoke (real downloads)", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["ZW_MODEL_SMOKE"] != nil))
struct ModelSmokeTests {
    private static func audio() throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: ProcessInfo.processInfo.environment["ZW_MODEL_SMOKE"]!))
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return buffer
    }

    /// Splits the take into 100 ms buffers, like the audio engine's stream.
    private static func chunks(of buffer: AVAudioPCMBuffer) -> [AVAudioPCMBuffer] {
        stride(from: 0, to: Int(buffer.frameLength), by: 1600).map { start in
            let count = min(1600, Int(buffer.frameLength) - start)
            let chunk = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(count))!
            chunk.frameLength = AVAudioFrameCount(count)
            chunk.floatChannelData![0].update(from: buffer.floatChannelData![0] + start, count: count)
            return chunk
        }
    }

    private func run(_ id: String) async throws {
        let start = ContinuousClock.now
        _ = try await ModelDownloadManager().download(variant: id) { _ in }
        #expect(ModelDownloadManager.isDownloaded(variant: id))
        print("[smoke] \(id) downloaded in \(ContinuousClock.now - start)")

        let engine = TranscriptionEngine()
        let loadStart = ContinuousClock.now
        try await engine.loadModel(id)
        await engine.setLanguage("en", translateToEnglish: false)
        await engine.setVocabulary(["zWhisper", "Nemotron"])
        print("[smoke] \(id) loaded in \(ContinuousClock.now - loadStart)")

        let collector = Task {
            var last = ""
            for await partial in engine.partials { last = partial; print("[smoke] \(id) partial: \(partial)") }
            return last
        }
        let audio = try Self.audio()
        for chunk in Self.chunks(of: audio) {
            await engine.feed(chunk)
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .seconds(1))
        let finalStart = ContinuousClock.now
        let transcript = try await engine.transcribeFinal(audio)
        print("[smoke] \(id) final in \(ContinuousClock.now - finalStart): \(transcript.text)")
        collector.cancel()
        let lower = transcript.text.lowercased()
        #expect(lower.contains("fox"))
        #expect(lower.contains("moon"))

        // A second session must not inherit the first one's audio.
        let again = try await engine.transcribeFinal(audio)
        #expect(again.text == transcript.text)
    }

    @Test func whisper() async throws { try await run("large-v3-v20240930_626MB") }
    @Test func whisperFull() async throws { try await run("large-v3-v20240930") }
    @Test func whisperTurbo() async throws { try await run("large-v3-v20240930_turbo") }
    @Test func parakeet() async throws { try await run(LocalModelFamily.parakeetID) }
    @Test func nemotron() async throws { try await run(LocalModelFamily.nemotronID) }
}
