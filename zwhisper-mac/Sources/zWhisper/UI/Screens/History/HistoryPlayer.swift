import AVFAudio
import Foundation

/// Playback for the History detail pane (§6.3): AVAudioPlayer with rate
/// support, 50ms playhead ticker.
@MainActor @Observable
final class HistoryPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func load(url: URL?) {
        stop()
        guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
            player = nil
            duration = 0
            currentTime = 0
            return
        }
        self.player = player
        player.enableRate = true
        player.rate = rate
        player.prepareToPlay()
        duration = player.duration
        currentTime = 0
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        if currentTime >= duration { seek(to: 0) }
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), duration)
        player?.currentTime = clamped
        currentTime = clamped
    }

    func skip(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        player?.rate = newRate
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    return
                }
            }
        }
    }
}
