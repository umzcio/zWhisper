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

        // §3.4: anchored below-left of the pill (prototype: left-0, top-7).
        panel.setFrameOrigin(NSPoint(
            x: anchorRect.minX,
            y: anchorRect.minY - size.height - 7
        ))
        panel.orderFrontRegardless()
        installDismissMonitors()
    }

    func dismiss() {
        panel?.orderOut(nil)
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
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
