import Foundation

/// Bar-height math for the popover waveform (spec §3.2). Plain class rather
/// than `@Observable`: it is mutated from TimelineView ticks, which already
/// drive redraws at display rate — observation would double-invalidate.
@MainActor
final class WaveformModel {
    enum State {
        case idle, live, settling
    }

    private(set) var state: State = .idle

    private var recent: [Float] = [] // newest last, capped at 25 (~500ms window)
    private var heights: [CGFloat] = []
    private var settleAt: [Date] = []

    func beginLive() {
        state = .live
        recent.removeAll()
    }

    /// Spec §3.2: bars collapse to 2px, staggered center-out over 300ms.
    func beginSettle(now: Date, barCount: Int) {
        guard state == .live else { return }
        state = .settling
        let mid = Double(barCount - 1) / 2
        settleAt = (0 ..< barCount).map { i in
            now.addingTimeInterval(abs(Double(i) - mid) / mid * 0.3)
        }
    }

    func reset() {
        state = .idle
        recent.removeAll()
        settleAt.removeAll()
    }

    /// Per-frame update mirroring Waveform.tsx: target = 2 + amp·(h−6) clamped
    /// to [2, h], exponential lerp `h += (target − h)·0.2`. During settle, each
    /// bar's target flips to 2px once its staggered delay elapses.
    /// `level` is the normalized (0…1) RMS for the newest sample; bars read a
    /// recency window symmetric about the center bar.
    func update(barCount: Int, maxHeight: CGFloat, level: Float, now: Date, reduceMotion: Bool = false) -> [CGFloat] {
        if heights.count != barCount {
            heights = [CGFloat](repeating: 2, count: barCount)
        }
        // §5.5 reduced motion: static bars, no lerp, no RMS feed.
        if reduceMotion {
            return (0 ..< barCount).map { i in
                max(2, 4 + abs(sin(Double(i) * 0.55)) * maxHeight * 0.5)
            }
        }
        switch state {
        case .idle:
            // §3.2 static bars: 4 + |sin(i·0.55)|·height·0.5
            for i in 0 ..< barCount {
                let target = max(2, 4 + abs(sin(Double(i) * 0.55)) * maxHeight * 0.5)
                heights[i] += (target - heights[i]) * 0.2
            }
        case .live:
            recent.append(level)
            if recent.count > 25 { recent.removeFirst() }
            let mid = Double(barCount - 1) / 2
            for i in 0 ..< barCount {
                let distance = Int(abs(Double(i) - mid).rounded())
                let index = max(0, recent.count - 1 - distance)
                let amp = CGFloat(recent.isEmpty ? 0 : recent[index])
                let target = 2 + amp * (maxHeight - 6)
                heights[i] += (target - heights[i]) * 0.2
            }
        case .settling:
            guard settleAt.count == barCount else {
                reset()
                return heights
            }
            var allCollapsed = true
            for i in 0 ..< barCount {
                if now < settleAt[i] { allCollapsed = false }
                let target: CGFloat = now >= settleAt[i] ? 2 : heights[i]
                heights[i] += (target - heights[i]) * 0.2
            }
            // Allow a lerp tail after the last stagger slot, then back to idle.
            if allCollapsed, let last = settleAt.last, now > last.addingTimeInterval(0.35) {
                reset()
            }
        }
        return heights.map { max(2, min(maxHeight, $0)) }
    }
}
