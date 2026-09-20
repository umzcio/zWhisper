import AVFAudio
import Accelerate
import SwiftUI

/// §6.3 WaveformStrip: 80px tall, surface-2/40, radius 8, hairline; 80 bars
/// (gap 3px, min 2px) computed from the session audio, blue→purple gradient
/// (§2.6 playback), played bars alpha 1 vs 0.3, click-to-seek, playhead =
/// 1px white/90 line + 8px handle dot.
struct WaveformStrip: View {
    let audioURL: URL?
    /// 0…1
    let progress: Double
    let onSeek: (Double) -> Void

    @State private var bars: [Float] = Array(repeating: 0.1, count: 80)

    var body: some View {
        GeometryReader { proxy in
            Canvas { graphics, size in
                let barCount = bars.count
                let gap: CGFloat = 3
                let barWidth = max(1, (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount))
                let progressWidth = size.width * min(max(progress, 0), 1)
                for (index, bar) in bars.enumerated() {
                    let height = max(2, CGFloat(bar) * size.height)
                    let x = CGFloat(index) * (barWidth + gap)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    let played = x + barWidth / 2 <= progressWidth
                    graphics.fill(
                        Path(roundedRect: rect, cornerRadius: min(2, barWidth / 2), style: .continuous),
                        with: .linearGradient(
                            Gradient(colors: [ZWColor.accentBlue, ZWColor.accentPurple]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: 0)
                        )
                    )
                    if !played {
                        graphics.fill(
                            Path(roundedRect: rect, cornerRadius: min(2, barWidth / 2), style: .continuous),
                            with: .color(ZWColor.surface2.opacity(0.7))
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    onSeek(min(max(value.location.x / proxy.size.width, 0), 1))
                }
            )
            .overlay(alignment: .leading) {
                // Playhead: 1px white/90 line + 8px handle dot (PLAYHEAD spring is M6 polish)
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 1)
                    .overlay(alignment: .top) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .offset(y: -4)
                    }
                    .offset(x: proxy.size.width * min(max(progress, 0), 1))
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 80)
        .background(ZWColor.surface2.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ZWColor.separator, lineWidth: 1)
        )
        .task(id: audioURL) {
            bars = await Self.loadBars(url: audioURL)
        }
    }

    /// 80 RMS buckets decoded from the session m4a, normalized 0…1.
    private static func loadBars(url: URL?) async -> [Float] {
        guard let url else { return Array(repeating: 0.1, count: 80) }
        return await Task.detached(priority: .utility) {
            guard let file = try? AVAudioFile(forReading: url) else {
                return Array(repeating: 0.1, count: 80)
            }
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
            else {
                return Array(repeating: 0.1, count: 80)
            }
            try? file.read(into: buffer)
            guard let data = buffer.floatChannelData?[0] else {
                return Array(repeating: 0.1, count: 80)
            }
            let total = Int(buffer.frameLength)
            let bucketSize = max(1, total / 80)
            var bars: [Float] = []
            var peak: Float = 0
            for bucket in 0 ..< 80 {
                let start = bucket * bucketSize
                guard start < total else { break }
                let end = min(start + bucketSize, total)
                var meanSquare: Float = 0
                vDSP_measqv(data + start, 1, &meanSquare, vDSP_Length(end - start))
                let rms = sqrt(meanSquare)
                bars.append(rms)
                peak = max(peak, rms)
            }
            while bars.count < 80 { bars.append(0) }
            guard peak > 0 else { return bars.map { _ in Float(0.1) } }
            return bars.map { max(0.06, $0 / peak) }
        }.value
    }
}
