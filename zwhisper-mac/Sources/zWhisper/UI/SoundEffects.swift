import AVFAudio

/// §6.6 sound effects styles applied to dictation events (record start/stop).
/// Subtle: 1240Hz sine, 90ms, gain 0.035. Classic: 760Hz, gain 0.09. None: silent.
/// Playback runs on a dedicated serial queue — AVAudioPlayer creation can
/// stall the main thread on audio-route contention.
enum ZWSoundEffects {
    enum Event {
        case recordStart, recordStop
    }

    static func play(_ event: Event, style: SettingsStore.SoundEffectsStyle) {
        guard style != .none else { return }
        let frequency = style == .subtle ? 1240.0 : 760.0
        let gain = style == .subtle ? 0.035 : 0.09
        queue.async {
            play(frequency: frequency, gain: gain, duration: 0.09)
        }
    }

    private static let queue = DispatchQueue(label: "app.zwhisper.soundeffects")
    /// Only touched on `queue` (serial), hence nonisolated(unsafe).
    nonisolated(unsafe) private static var player: AVAudioPlayer?

    /// Synthesizes a decaying sine blip as an in-memory 16-bit mono WAV.
    /// Must only be called on `queue`.
    private static func play(frequency: Double, gain: Double, duration: Double) {
        let sampleRate = 44_100
        let count = Int(Double(sampleRate) * duration)
        var pcm = Data()
        pcm.reserveCapacity(count * 2)
        for i in 0 ..< count {
            let t = Double(i) / Double(sampleRate)
            let envelope = exp(-t * 30)
            let sample = Int16(sin(2 * .pi * frequency * t) * gain * envelope * Double(Int16.max))
            var little = sample.littleEndian
            Swift.withUnsafeBytes(of: &little) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        wav.appendLE(UInt32(36 + pcm.count))
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        wav.appendLE(UInt32(16))
        wav.appendLE(UInt16(1)) // PCM
        wav.appendLE(UInt16(1)) // mono
        wav.appendLE(UInt32(sampleRate))
        wav.appendLE(UInt32(sampleRate * 2))
        wav.appendLE(UInt16(2))
        wav.appendLE(UInt16(16))
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        wav.appendLE(UInt32(pcm.count))
        wav.append(pcm)
        player = try? AVAudioPlayer(data: wav)
        player?.play()
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt32) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt16) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
