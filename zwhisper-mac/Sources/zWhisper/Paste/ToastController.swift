import AppKit
import SwiftUI

/// Hosts the §4.3 result toast in a transient borderless NSPanel at the
/// bottom-right of the screen (24px margins above `visibleFrame`, so it clears
/// a visible Dock — the prototype's "bottom 80px" included its faux dock).
/// Auto-dismisses after 6s; the toast lives independently of the popover (§4).
@MainActor
final class ToastController {
    private(set) var toast: ResultToast?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ResultToastView>?
    private var dismissTask: Task<Void, Never>?
    private var undoHandler: (() -> Void)?
    private var reprocessHandler: (() -> Void)?

    /// Shows the toast (6s auto-dismiss). Handlers: "Undo paste" and
    /// "Reprocess" (§4.3).
    func show(_ toast: ResultToast, onUndo: @escaping () -> Void, onReprocess: @escaping () -> Void) {
        self.toast = toast
        undoHandler = onUndo
        reprocessHandler = onReprocess
        dismissTask?.cancel()
        present()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func undoPaste() {
        guard toast?.canUndo == true else { return }
        undoHandler?()
        toast?.clipboardRestored = true
        refreshContent()
        // "Clipboard restored" holds for 1.8s, then dismiss (§3.7).
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        toast = nil
    }

    private func present() {
        guard let toast else { return }
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 288, height: 76),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false // the SwiftUI view draws the §2.5 popover shadow
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        refreshContent()
        if let screen = NSScreen.main ?? NSScreen.screens.first, let panel {
            let frame = panel.frame
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - frame.width - 24,
                y: visible.minY + 24
            ))
        }
        panel?.orderFrontRegardless()
    }

    private func refreshContent() {
        guard let toast, let panel else { return }
        let view = ResultToastView(
            toast: toast,
            onUndo: { [weak self] in self?.undoPaste() },
            onReprocess: { [weak self] in
                self?.dismiss()
                self?.reprocessHandler?()
            }
        )
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = panel.contentView?.bounds ?? .zero
            hostingView.autoresizingMask = [.width, .height]
            panel.contentView = hostingView
            self.hostingView = hostingView
        }
        if let hostingView = self.hostingView {
            panel.setContentSize(hostingView.fittingSize)
        }
    }
}
