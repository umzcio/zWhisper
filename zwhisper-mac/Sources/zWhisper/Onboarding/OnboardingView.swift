import AppKit
import ApplicationServices
import AVFAudio
import FoundationModels
import SwiftUI

/// First-run onboarding (architecture §3.10, §8): ordered, skippable-per-step —
/// Welcome → Microphone → Accessibility → Default model download → Apple
/// Intelligence check → "Try it" (guided first dictation). Window 560×420,
/// vibrancy, radius 12.
struct OnboardingView: View {
    let appState: AppState
    let close: () -> Void

    private enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double, bytesPerSecond: Double)
        case done
        case failed
    }

    @State private var step = 0
    @State private var forward = true
    @State private var micGranted = false
    @State private var micDenied = false
    @State private var axTrusted = false
    @State private var axPollTask: Task<Void, Never>?
    @State private var downloadState: DownloadState = .idle
    @State private var downloadTask: Task<Void, Never>?
    @State private var aiAvailable = false

    private let stepCount = 6
    private let modelName = ModelDownloadManager.defaultModelName

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepContent
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)),
                        removal: .opacity.combined(with: .offset(x: forward ? -24 : 24))
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 560, height: 420)
        .background(
            VisualEffect(material: .underWindowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .onDisappear {
            // Closing the window by any path counts as completing/skipping (§8).
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            card(icon: nil, title: "Welcome to zWhisper",
                 subtitle: "On-device dictation: speak, and zWhisper types for you in any app.") {}
        case 1:
            card(icon: "mic.fill", title: "Microphone access",
                 subtitle: "zWhisper hears you only while you dictate. Audio never leaves your Mac.") {
                if micGranted {
                    grantedRow("Microphone access granted")
                } else {
                    VStack(spacing: 10) {
                        primaryButton("Grant microphone access") { requestMic() }
                        if micDenied {
                            Text("Access denied — zWhisper can't record without it.")
                                .font(.system(size: 12))
                                .foregroundStyle(ZWColor.accentRed)
                            Button("Open System Settings") { openSystemSettings("Privacy_Microphone") }
                                .buttonStyle(ZWButtonStyle())
                                .font(.system(size: 12))
                                .foregroundStyle(ZWColor.accentBlue)
                        }
                    }
                }
            }
            .onAppear { refreshMicStatus() }
        case 2:
            card(icon: "hand.point.up.left.fill", title: "Accessibility access",
                 subtitle: "Auto-paste types at the caret in any app, and push-to-talk uses it to avoid stuck recordings.") {
                if axTrusted {
                    grantedRow("Accessibility access granted")
                } else {
                    VStack(spacing: 10) {
                        primaryButton("Grant accessibility access") { requestAccessibility() }
                        // §8: AX is non-blocking — the app still fully transcribes.
                        Text("Without it, auto-paste degrades to copy-to-clipboard (⌘V to paste).")
                            .font(.system(size: 12))
                            .foregroundStyle(ZWColor.text3)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .onAppear { startAccessibilityPolling() }
            .onDisappear { axPollTask?.cancel(); axPollTask = nil }
        case 3:
            card(icon: "arrow.down.circle.fill", title: "Download the speech model",
                 subtitle: "zWhisper transcribes on-device with the \(modelName) model. This is a one-time download.") {
                switch downloadState {
                case .done:
                    grantedRow("Model ready")
                case .downloading(let progress, let bytesPerSecond):
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .frame(width: 320)
                        HStack {
                            Text("\(Int(progress * 100))%")
                            Spacer()
                            Text(bytesPerSecond > 0 ? String(format: "%.1f MB/s", bytesPerSecond / 1_048_576) : "…")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(ZWColor.text2)
                        .frame(width: 320)
                        Button("Cancel") { cancelDownload() }
                            .buttonStyle(ZWButtonStyle())
                            .font(.system(size: 12))
                            .foregroundStyle(ZWColor.text2)
                    }
                case .failed:
                    VStack(spacing: 10) {
                        Label("Download failed — check your connection.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(ZWColor.accentRed)
                        secondaryButton("Retry") { startDownload() }
                    }
                case .idle:
                    primaryButton("Download model") { startDownload() }
                }
            }
            .onAppear { onModelStepAppeared() }
        case 4:
            card(icon: "sparkles", title: "Apple Intelligence",
                 subtitle: "Modes like Email and Write for me rewrite your words on-device.") {
                if aiAvailable {
                    grantedRow("Apple Intelligence ready — modes rewrite on-device")
                } else {
                    // §8: informational, non-blocking.
                    Label("Modes other than Voice Note need Apple Intelligence or a cloud key.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(ZWColor.accentOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ZWColor.accentOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .onAppear {
                if case .available = SystemLanguageModel.default.availability {
                    aiAvailable = true
                } else {
                    aiAvailable = false
                }
            }
        default:
            card(icon: "keyboard", title: "Try it now",
                 subtitle: "Hold the right ⌘ key and speak — or press ⌥⇧Space to toggle. Release, and zWhisper types for you.") {
                primaryButton("Start dictating") {
                    finish()
                    appState.startDictation()
                }
            }
        }
    }

    private func card<Content: View>(
        icon: String?,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 12) {
            if let icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [ZWColor.accentBlue, ZWColor.accentTeal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
            } else {
                AnimatedLogoView()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ZWColor.text1)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(ZWColor.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            content()
        }
        .padding(.horizontal, 40)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button { go(to: step - 1, forward: false) } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text2)
            }
            .buttonStyle(ZWButtonStyle())
            .disabled(step == 0)
            .opacity(step == 0 ? 0 : 1)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0 ..< stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? ZWColor.accentBlue : ZWColor.surface3)
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if step == stepCount - 1 {
                secondaryButton("Done") { finish() }
            } else {
                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Skip") { skipStep() }
                            .buttonStyle(ZWButtonStyle())
                            .font(.system(size: 13))
                            .foregroundStyle(ZWColor.text3)
                    }
                    primaryButton("Continue") { go(to: step + 1, forward: true) }
                        .disabled(step == 3 && isDownloading)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            ZWColor.separator.frame(height: 1)
        }
    }

    // MARK: Actions

    private func go(to newStep: Int, forward: Bool) {
        guard (0 ..< stepCount).contains(newStep) else { return }
        self.forward = forward
        withAnimation(AppState.springDefault) {
            step = newStep
        }
    }

    private func skipStep() {
        if step == 3 { cancelDownload() }
        go(to: step + 1, forward: true)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        // AppState defers the launch model load while onboarding is up; run it now.
        Task { await appState.prepareTranscription() }
        close()
    }

    private func refreshMicStatus() {
        micGranted = AVAudioApplication.shared.recordPermission == .granted
    }

    private func requestMic() {
        Task { @MainActor in
            let granted = await AVAudioApplication.requestRecordPermission()
            micGranted = granted
            micDenied = !granted
        }
    }

    private func requestAccessibility() {
        // Literal key: kAXTrustedCheckOptionPrompt is a C var (not concurrency-safe).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        startAccessibilityPolling()
    }

    /// §8: poll AXIsProcessTrusted() to detect the grant (no callback exists).
    private func startAccessibilityPolling() {
        guard axPollTask == nil else { return }
        axPollTask = Task { @MainActor in
            while !Task.isCancelled {
                axTrusted = AXIsProcessTrusted()
                if axTrusted { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var isDownloading: Bool {
        if case .downloading = downloadState { return true }
        return false
    }

    private func onModelStepAppeared() {
        if ModelDownloadManager.isDownloaded(variant: modelName) {
            downloadState = .done
        } else if downloadState == .idle {
            startDownload()
        }
    }

    /// §8 step 4: the real download path (§3.10: reuse ModelDownloadManager).
    private func startDownload() {
        let tracker = OnboardingSpeedTracker()
        downloadTask = Task { @MainActor in
            downloadState = .downloading(progress: 0, bytesPerSecond: 0)
            do {
                _ = try await ModelDownloadManager().download(variant: modelName) { progress in
                    let speed = tracker.sample(bytes: progress.completedUnitCount)
                    Task { @MainActor in
                        if case .downloading = downloadState {
                            downloadState = .downloading(progress: progress.fractionCompleted, bytesPerSecond: speed)
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                downloadState = .done
                // Load the freshly downloaded model so "Try it" records immediately.
                await appState.prepareTranscription()
            } catch {
                downloadState = Task.isCancelled ? .idle : .failed
            }
        }
    }

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .idle
    }

    private func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Controls

    private func grantedRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ZWColor.accentGreen)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(ZWColor.accentBlue, in: Capsule())
        }
        .buttonStyle(ZWButtonStyle())
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ZWColor.text1)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(ZWColor.surface3, in: Capsule())
        }
        .buttonStyle(ZWButtonStyle())
    }
}

/// Tracks download throughput across Progress callbacks (same sampling as the
/// §6.4 Models rows).
private final class OnboardingSpeedTracker: @unchecked Sendable {
    private var lastBytes: Int64 = 0
    private var lastTime = ContinuousClock.now

    /// Returns bytes/second since the previous sample (0 until 200ms elapse).
    func sample(bytes: Int64) -> Double {
        let now = ContinuousClock.now
        let elapsed = now - lastTime
        guard elapsed > .milliseconds(200), bytes > lastBytes else { return 0 }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let speed = Double(bytes - lastBytes) / seconds
        lastBytes = bytes
        lastTime = now
        return speed
    }
}

/// Vibrancy backdrop (window 560×420, radius 12 applied by the caller's clip).
private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
