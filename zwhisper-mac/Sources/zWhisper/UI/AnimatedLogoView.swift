import AVKit
import SwiftUI

/// The midjourney-animated Z logo (5s, h264) looping muted. Used wherever the
/// static app icon would sit: docked rest pill, onboarding welcome.
struct AnimatedLogoView: NSViewRepresentable {
    func makeNSView(context: Context) -> AnimatedLogoNSView {
        AnimatedLogoNSView()
    }

    func updateNSView(_ nsView: AnimatedLogoNSView, context: Context) {}
}

final class AnimatedLogoNSView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        guard let url = Bundle.main.url(forResource: "zwhisper-logo", withExtension: "mp4") else { return }
        let item = AVPlayerItem(url: url)
        player.isMuted = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func makeBackingLayer() -> CALayer {
        AVPlayerLayer()
    }

    private var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }
}
