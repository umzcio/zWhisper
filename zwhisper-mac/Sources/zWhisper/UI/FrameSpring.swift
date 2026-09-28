import AppKit

/// Velocity-carrying spring driver for NSWindow frame animation.
///
/// NSAnimationContext only offers fixed-duration easing curves; this integrates
/// a damped harmonic oscillator per tick instead, so re-targeting mid-flight
/// starts from the live on-screen value AND its velocity — interruptible, no
/// "brick wall" at a reversal (Designing Fluid Interfaces, WWDC 2018).
///
/// Maps SwiftUI's designer-facing spring params: ω = 2π/response,
/// stiffness = ω², damping = 2·dampingFraction·ω. dampingFraction 1.0 is
/// critically damped (no overshoot) — the right default for moves/resizes.
@MainActor
final class FrameSpring {
    private var timer: Timer?
    private var frame: NSRect = .zero
    private var vx: CGFloat = 0
    private var vy: CGFloat = 0
    private var vw: CGFloat = 0
    private var vh: CGFloat = 0

    /// Spring `window`'s frame to `target`. Safe to call mid-flight: the
    /// animation re-targets from the presentation value with carried velocity.
    func animate(
        _ window: NSWindow,
        to target: NSRect,
        response: Double = 0.4,
        dampingFraction: Double = 1.0
    ) {
        let inFlight = timer != nil
        timer?.invalidate()
        timer = nil
        if AppState.reduceMotion {
            window.setFrame(target, display: true)
            return
        }
        if !inFlight {
            // Adopt the live on-screen frame; a cold start has zero velocity.
            frame = window.frame
            vx = 0
            vy = 0
            vw = 0
            vh = 0
        }

        let omega = CGFloat(2 * Double.pi / response)
        let stiffness = omega * omega
        let damping = CGFloat(2 * dampingFraction) * omega
        let dt: CGFloat = 1.0 / 120

        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(dt), repeats: true) {
            [weak self, weak window] timer in
            guard let self, let window else {
                timer.invalidate()
                return
            }
            func step(_ value: inout CGFloat, _ velocity: inout CGFloat, target: CGFloat) {
                let acceleration = -stiffness * (value - target) - damping * velocity
                velocity += acceleration * dt
                value += velocity * dt
            }
            step(&frame.origin.x, &vx, target: target.minX)
            step(&frame.origin.y, &vy, target: target.minY)
            step(&frame.size.width, &vw, target: target.width)
            step(&frame.size.height, &vh, target: target.height)

            let settled = abs(frame.minX - target.minX) < 0.25
                && abs(frame.minY - target.minY) < 0.25
                && abs(frame.width - target.width) < 0.25
                && abs(frame.height - target.height) < 0.25
                && abs(vx) < 4 && abs(vy) < 4 && abs(vw) < 4 && abs(vh) < 4
            if settled {
                frame = target
                window.setFrame(target, display: true)
                timer.invalidate()
                self.timer = nil
            } else {
                window.setFrame(frame, display: true)
            }
        }
    }
}
