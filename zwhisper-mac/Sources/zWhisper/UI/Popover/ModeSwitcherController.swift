import AppKit
import SwiftUI

/// Hosts the §3.4 ModeSwitcher in a small borderless panel anchored below the
/// popover's mode pill. (SwiftUI `.popover` does not present reliably inside a
/// borderless non-activating NSPanel, hence a dedicated panel.) Dismisses on
/// outside click or selection.
@MainActor
final class ModeSwitcherController {
    private var panel: NSPanel?
    private weak var appState: AppState?
    private var eventMonitors: [Any] = []

    init(appState: AppState) {
        self.appState = appState
    }

    var isOpen: Bool { panel?.isVisible ?? false }

    func toggle(below anchorRect: NSRect) {
        isOpen ? dismiss() : show(below: anchorRect)
    }

    func show(below anchorRect: NSRect) {
        guard let appState else { return }
        let view = ModeSwitcherView(appState: appState) { [weak self] in
            self?.dismiss()
        }
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let vibrancy = NSVisualEffectView()
            vibrancy.material = .popover
            vibrancy.blendingMode = .behindWindow
            vibrancy.state = .active
            vibrancy.wantsLayer = true
            vibrancy.layer?.cornerRadius = 14
            vibrancy.layer?.masksToBounds = true
            vibrancy.layer?.borderWidth = 0.5
            vibrancy.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
            panel.contentView = vibrancy
            self.panel = panel
        }
        guard let panel, let vibrancy = panel.contentView else { return }

        hostingView.frame = vibrancy.bounds
        hostingView.autoresizingMask = [.width, .height]
        vibrancy.subviews.forEach { $0.removeFromSuperview() }
        vibrancy.addSubview(hostingView)
        panel.setContentSize(size)

        // §3.4: anchored below-left of the pill — flipping above it when the
        // pill sits too close to the bottom edge (docked indicator).
        var origin = NSPoint(
            x: anchorRect.minX,
            y: anchorRect.minY - size.height - 7
        )
        var flippedAbove = false
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            if origin.y < screen.visibleFrame.minY + 4 {
                origin.y = anchorRect.maxY + 7
                flippedAbove = true
            }
            // Keep the panel on-screen — the docked pill hugs the right edge.
            origin.x = min(origin.x, screen.visibleFrame.maxX - size.width - 8)
            origin.x = max(origin.x, screen.visibleFrame.minX + 8)
        }
        panel.setFrameOrigin(origin)

        // Materialize from the pill's edge; the exit retraces the same path.
        if AppState.reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            let drift: CGFloat = flippedAbove ? -6 : 6
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + drift))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(origin)
                panel.animator().alphaValue = 1
            }
        }
        flipped = flippedAbove
        installDismissMonitors()
    }

    private var flipped = false

    func dismiss() {
        guard let panel, panel.isVisible else {
            for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
            eventMonitors.removeAll()
            return
        }
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        if AppState.reduceMotion {
            panel.orderOut(nil)
            return
        }
        let drift: CGFloat = flipped ? -6 : 6
        let exitOrigin = NSPoint(x: panel.frame.minX, y: panel.frame.minY + drift)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(exitOrigin)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        })
    }

    /// Dismiss on outside pointer-down (§3.4).
    private func installDismissMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        } {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let panel = self?.panel, event.window !== panel {
                Task { @MainActor in self?.dismiss() }
            }
            return event
        } {
            eventMonitors.append(local)
        }
    }
}
