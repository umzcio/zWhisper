import AppKit
import SwiftUI

/// Borderless NSPanel hosting the recording popover (architecture §2, spec §3.1/§8).
/// Vibrancy background, corner radius 14, hairline + shadow per §2.5. Draggable by
/// background; Main/Mini frame changes are animated with the top edge anchored.
@MainActor
final class PopoverController {
    /// §3.1 sizes: Main 420×240, Mini 220×64.
    static let mainSize = NSSize(width: 420, height: 240)
    static let miniSize = NSSize(width: 220, height: 64)

    private let panel: NSPanel
    private weak var appState: AppState?
    private var hasBeenPositioned = false

    /// Floating top-center (§3.1) or persistent bottom-right docked indicator.
    var placement: SettingsStore.PopoverPlacement = .top {
        didSet {
            if placement != oldValue {
                hasBeenPositioned = false
                reposition(animated: true)
            }
        }
    }

    init(appState: AppState) {
        self.appState = appState

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.mainSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let vibrancy = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.mainSize))
        vibrancy.material = .popover
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 14
        vibrancy.layer?.masksToBounds = true
        // Hairline from the §2.5 popover shadow token: 0 0 0 0.5px white @ 10% (dark default)
        vibrancy.layer?.borderWidth = 0.5
        vibrancy.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        let hostingView = PopoverHostingView(rootView: PopoverContentView(appState: appState))
        hostingView.frame = vibrancy.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onDoubleClick = { [weak appState] in
            appState?.togglePopoverSize()
        }
        vibrancy.addSubview(hostingView)

        panel.contentView = vibrancy
        self.panel = panel
    }

    /// Orders the panel in while the content is still in its pre-entrance state;
    /// AppState then plays the SPRING_POP summon animation.
    func present() {
        if !hasBeenPositioned {
            reposition(animated: false)
        }
        panel.orderFrontRegardless()
    }

    /// Shows the persistent docked indicator (idle mini) at launch / on
    /// placement change — no summon semantics.
    func presentPersistent() {
        reposition(animated: false)
        panel.orderFrontRegardless()
    }

    /// Orders the panel out once the exit animation has had time to finish.
    func dismissAfterExitAnimation() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.appState?.isPopoverOpen == false else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Animated Main ↔ Mini frame change (§3.1), anchored per placement.
    func animateFrame(to size: AppState.PopoverSize) {
        let newSize = size == .main ? Self.mainSize : Self.miniSize
        let old = panel.frame
        guard old.size != newSize else { return }
        let origin: NSPoint
        if placement == .bottomRight {
            origin = dockedOrigin(for: newSize)
        } else {
            origin = NSPoint(
                x: old.midX - newSize.width / 2,
                y: old.maxY - newSize.height
            )
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.31
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(origin: origin, size: newSize), display: true)
        }
        hasBeenPositioned = true
    }

    /// Screen rect of the mode pill (fixed slot in the top row), used to
    /// anchor the §3.4 ModeSwitcher panel below-left of the pill.
    func modePillScreenRect() -> NSRect {
        let frame = panel.frame
        // Top row: padding 12 → context dot (12) → spacing 8 → pill (~22px tall).
        return NSRect(x: frame.minX + 32, y: frame.maxY - 12 - 22, width: 1, height: 22)
    }

    private func reposition(animated: Bool) {
        let size = panel.frame.size
        let origin: NSPoint
        if placement == .bottomRight {
            origin = dockedOrigin(for: size)
        } else {
            // Spec §3.1: top-center of the screen, 40px below the menu bar.
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            let frame = screen.visibleFrame
            origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 40
            )
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.31
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrameOrigin(origin)
            }
        } else {
            panel.setFrameOrigin(origin)
        }
        hasBeenPositioned = true
    }

    /// Docked indicator: bottom-right of the screen, 24px margins above
    /// `visibleFrame` (clears a visible Dock).
    private func dockedOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        let frame = screen.visibleFrame
        return NSPoint(
            x: frame.maxX - size.width - 24,
            y: frame.minY + 24
        )
    }
}

/// NSHostingView that keeps the panel draggable by its background (§3.1) and
/// reports double-clicks for the Main ↔ Mini toggle.
private final class PopoverHostingView: NSHostingView<PopoverContentView> {
    var onDoubleClick: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }
}
