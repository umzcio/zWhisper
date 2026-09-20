import AVFAudio
import Accelerate

enum AudioCaptureError: Error {
    case inputUnavailable
    case converterUnavailable
}

/// Buffers cross exactly one ownership boundary (tap → engine consumer, and
/// engine → transcription) via single-consumer streams. Swift 6 requires this
/// conformance to keep the architecture §3.2 protocol shape.
extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}

/// Architecture §3.2 contract. Implementations run on their own actor (hence
/// `async` methods); streams are single-consumer (AppState forwards levels).
protocol AudioCaptureEngineProtocol: Sendable {
    /// RMS per tap buffer (~21ms tick at bufferSize 1024 @ 48kHz) → waveform + input meter.
    var levels: AsyncStream<Float> { get }
    /// 16kHz mono Float32 voiced buffers → transcription (M3).
    var buffers: AsyncStream<AVAudioPCMBuffer> { get }
    /// Settings → Sound "Dynamic normalization" (§6.6): pre-RMS gain ramp on the tap buffer.
    func setNormalizationEnabled(_ enabled: Bool) async
    /// Settings → Sound "Silence removal" + aggressiveness 0–100 (§6.6).
    func setSilenceRemoval(enabled: Bool, aggressiveness: Int) async
    func start() async throws
    /// Full-session 16kHz mono buffer for the final transcription pass (§5).
    func stop() async -> AVAudioPCMBuffer
    /// Relative path (under Application Support/zWhisper/) of the session's m4a
    /// while recording and after stop; nil after cancel (§7 audioPath).
    var sessionAudioRelativePath: String? { get async }
    /// Stop capture and discard the session (cancel path — no file kept).
    func cancel() async
    /// Levels-only capture for the Settings → Sound input meter.
    func startMetering() async throws
    func stopMetering() async
}

/// Settings read on the real-time tap thread. Written from the engine actor;
/// races on these scalars are benign (worst case one buffer of stale gain).
private final class RTSettings: @unchecked Sendable {
    var normalizationEnabled = true
    var gain: Float = 1
    var peak: Float = 0
}

/// Architecture §5 pipeline: input tap → RMS (+ optional pre-RMS AGC gain) →
/// 16kHz/mono/Float32 conversion → VAD gate → buffers stream; the full session
/// accumulates regardless of the gate and is written to an m4a for History (§6.3).
actor AudioCaptureEngine: AudioCaptureEngineProtocol {
    nonisolated let levels: AsyncStream<Float>
    nonisolated let buffers: AsyncStream<AVAudioPCMBuffer>

    private nonisolated let levelContinuation: AsyncStream<Float>.Continuation
    private nonisolated let bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    /// Re-created per recording session: AsyncStream is single-iteration, so a
    /// second consumer on a used stream silently receives nothing.
    private var packetContinuation: AsyncStream<Packet>.Continuation!
    private var packets: AsyncStream<Packet>!

    private typealias Packet = (buffer: AVAudioPCMBuffer, rms: Float)

    private enum Mode {
        case off, metering, recording
    }

    private let engine = AVAudioEngine()
    private let audioDirectory: URL
    private let rt = RTSettings()
    private var mode: Mode = .off
    private var consumerTask: Task<Void, Never>?

    private var nativeFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    /// Whisper's expected format (§5): 16kHz mono Float32.
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private var sessionSamples: [Float] = []
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private(set) var sessionAudioRelativePath: String?

    private var silenceRemovalEnabled = true
    /// Aggressiveness 0–100 → gate threshold −60dB…−15dB.
    private var silenceThresholdDB: Float = -42

    init(audioDirectory: URL? = nil) {
        self.audioDirectory = audioDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("zWhisper/audio", isDirectory: true)

        var levelContinuation: AsyncStream<Float>.Continuation!
        levels = AsyncStream { levelContinuation = $0 }
        self.levelContinuation = levelContinuation

        var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        buffers = AsyncStream { bufferContinuation = $0 }
        self.bufferContinuation = bufferContinuation
    }

    func setNormalizationEnabled(_ enabled: Bool) {
        rt.normalizationEnabled = enabled
        if !enabled { rt.gain = 1; rt.peak = 0 }
    }

    func setSilenceRemoval(enabled: Bool, aggressiveness: Int) {
        silenceRemovalEnabled = enabled
        let clamped = min(max(aggressiveness, 0), 100)
        silenceThresholdDB = -60 + Float(clamped) / 100 * 45
    }

    func start() async throws {
        try installPipeline()
        sessionSamples.removeAll()
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let fileURL = audioDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        audioFileURL = fileURL
        sessionAudioRelativePath = "audio/\(fileURL.lastPathComponent)"
        mode = .recording
        try startEngine()
    }

    /// Architecture §3.2: full-session 16kHz mono buffer for the final pass.
    func stop() -> AVAudioPCMBuffer {
        tearDownCapture(deleteSessionFile: false)
        let count = sessionSamples.count
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(count))
        else {
            return AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1)!
        }
        buffer.frameLength = AVAudioFrameCount(count)
        sessionSamples.withUnsafeBytes { src in
            if let base = src.baseAddress {
                memcpy(buffer.floatChannelData![0], base, count * MemoryLayout<Float>.size)
            }
        }
        return buffer
    }

    func cancel() {
        tearDownCapture(deleteSessionFile: true)
    }

    func startMetering() async throws {
        guard mode == .off else { return }
        try installPipeline()
        mode = .metering
        try startEngine()
    }

    func stopMetering() {
        guard mode == .metering else { return }
        tearDownCapture(deleteSessionFile: false)
    }

    // MARK: - Pipeline

    private func installPipeline() throws {
        tearDownCapture(deleteSessionFile: false)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.inputUnavailable
        }
        nativeFormat = format
        guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }
        self.converter = converter

        let rt = self.rt
        let levelContinuation = self.levelContinuation
        let (packets, packetContinuation) = AsyncStream<Packet>.makeStream()
        self.packets = packets
        self.packetContinuation = packetContinuation
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let copy = Self.copy(buffer) else { return }
            if rt.normalizationEnabled {
                rt.applyGain(to: copy)
            }
            let rms = copy.rms
            levelContinuation.yield(rms)
            packetContinuation.yield((copy, rms))
        }

        consumerTask = Task { [weak self] in
            guard let self else { return }
            for await packet in packets {
                await self.consume(packet)
            }
        }
    }

    private func startEngine() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    private func tearDownCapture(deleteSessionFile: Bool) {
        if engine.inputNode.numberOfInputs > 0 {
            engine.inputNode.removeTap(onBus: 0)
        }
        engine.stop()
        consumerTask?.cancel()
        consumerTask = nil
        converter = nil
        nativeFormat = nil
        audioFile = nil
        if deleteSessionFile, let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioFileURL = nil
        if deleteSessionFile {
            sessionSamples.removeAll()
            sessionAudioRelativePath = nil
        }
        mode = .off
    }

    private func consume(_ packet: Packet) {
        guard mode == .recording, let converter, let nativeFormat else { return }
        let ratio = targetFormat.sampleRate / nativeFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(packet.buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var error: NSError?
        var provided = false
        converter.convert(to: converted, error: &error) { _, status in
            guard !provided else {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return packet.buffer
        }
        guard error == nil, converted.frameLength > 0 else { return }

        let voiced = !silenceRemovalEnabled || Self.db(packet.rms) > silenceThresholdDB
        if voiced {
            bufferContinuation.yield(converted)
        }
        let count = Int(converted.frameLength)
        sessionSamples.append(contentsOf: UnsafeBufferPointer(start: converted.floatChannelData![0], count: count))
        try? audioFile?.write(from: converted)
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return nil }
        copy.frameLength = buffer.frameLength
        for channel in 0 ..< Int(buffer.format.channelCount) {
            memcpy(
                copy.floatChannelData![channel],
                buffer.floatChannelData![channel],
                Int(buffer.frameLength) * MemoryLayout<Float>.size
            )
        }
        return copy
    }

    static func db(_ rms: Float) -> Float {
        20 * log10(max(rms, 1e-7))
    }
}

private extension RTSettings {
    /// Simple AGC (§5 "Dynamic normalization"): peak envelope with instant
    /// attack / slow release, gain smoothed toward 0.5/peak, clamped 1…6×.
    func applyGain(to buffer: AVAudioPCMBuffer) {
        let frames = vDSP_Length(buffer.frameLength)
        for channel in 0 ..< Int(buffer.format.channelCount) {
            let data = buffer.floatChannelData![channel]
            var maxMagnitude: Float = 0
            vDSP_maxmgv(data, 1, &maxMagnitude, frames)
            peak = max(maxMagnitude, peak * 0.995)
            let target = min(max(0.5 / max(peak, 1e-4), 1), 6)
            gain += (target - gain) * 0.1
            var g = gain
            vDSP_vsmul(data, 1, &g, data, 1, frames)
        }
    }
}

private extension AVAudioPCMBuffer {
    var rms: Float {
        guard frameLength > 0, let data = floatChannelData?[0] else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(data, 1, &meanSquare, vDSP_Length(frameLength))
        return sqrt(meanSquare)
    }
}
