import SwiftUI

/// Recording popover chrome (spec §3.1). M2 wires the idle → recording states
/// with live waveform, timer, and session capture; teleprompter streaming and
/// the transcribing/processing/pasted phases arrive with M3–M5.
struct PopoverContentView: View {
    let appState: AppState

    @State private var hovering = false
    @State private var pillPulsing = false
    @State private var glowPulse = false

    private var isMain: Bool { appState.popoverSize == .main }
    private var isRecording: Bool {
        if case .recording = appState.phase { return true }
        return false
    }

    /// Transcribing/processing/pasting/pasted keep the recording controls visible but disabled (§3.1).
    private var isBusy: Bool {
        switch appState.phase {
        case .transcribing, .processing, .pasting, .pasted: return true
        case .idle, .recording: return false
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Watermark logo: 64px, 3% opacity, top-center (§3.1)
            Image(systemName: "waveform")
                .font(.system(size: 64))
                .foregroundStyle(ZWColor.text1.opacity(0.03))
                .padding(.top, 20)

            VStack(spacing: 0) {
                topRow
                WaveformView(appState: appState, barCount: isMain ? 48 : 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 8)
                if isMain {
                    teleprompter
                }
                if isMain || isRecording || isBusy {
                    bottomRow
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(appState.popoverAppeared || AppState.reduceMotion ? 1 : (appState.popoverExitStyle == .pasted ? 0.9 : 0.85))
        .opacity(appState.popoverAppeared ? 1 : 0)
        .offset(y: appState.popoverAppeared || AppState.reduceMotion ? 0 : (appState.popoverExitStyle == .pasted ? -4 : -8))
        .onHover { hovering = $0 }
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: appState.cancelShakeTrigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            // Cancel shake: x [0, −8, 8, −4, 0] over 0.4s (§3.1 `cancelled`)
            KeyframeTrack(\.self) {
                LinearKeyframe(-8, duration: 0.1)
                LinearKeyframe(8, duration: 0.1)
                LinearKeyframe(-4, duration: 0.1)
                LinearKeyframe(0, duration: 0.1)
            }
        }
        .animation(AppState.springDefault, value: appState.popoverSize)
        .animation(AppState.springDefault, value: isRecording)
    }

    /// §3.1 top row: context dot → mode pill → spacer → recording timer (Main,
    /// recording only) → resize toggle.
    private var topRow: some View {
        HStack(spacing: 8) {
            // §3.1 context dot: surface-3 default; purple + pulsing halo + tooltip when captured
            ZStack {
                if appState.contextCaptured {
                    Circle()
                        .fill(ZWColor.accentPurple.opacity(0.35))
                        .frame(width: 24, height: 24)
                        .scaleEffect(glowPulse ? 1.15 : 0.9)
                        .opacity(glowPulse ? 0.5 : 1)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: glowPulse)
                }
                Circle()
                    .fill(appState.contextCaptured ? ZWColor.accentPurple : ZWColor.surface3)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 12, height: 12)
            .help(contextTooltip)
            .onAppear { glowPulse = true }
            modePill
            Spacer(minLength: 0)
            if isMain, case let .recording(startedAt) = appState.phase {
                RecordingTimer(startedAt: startedAt)
            }
            Button(action: appState.togglePopoverSize) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13))
                    .foregroundStyle(ZWColor.text3)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ZWButtonStyle(hoverScale: 1.08, pressScale: 0.85))
            .help(isMain ? "Shrink to Mini" : "Expand to Main")
        }
    }

    /// §3.1 context-dot tooltip: "Context captured: {app} selection + clipboard".
    private var contextTooltip: String {
        guard let context = appState.capturedContext else { return "No context captured" }
        var parts = ["Context captured: \(context.frontmostApp)"]
        if context.selectedText != nil { parts.append("selection") }
        if context.clipboard != nil { parts.append("clipboard") }
        return parts.joined(separator: " + ")
    }

    /// Compact ModePill (§3.4): hairline, surface-2/80, icon 11px in mode color,
    /// label 10px/600 uppercase, chevron 10px. Pulses 1.15→1 on mode change
    /// (§3.1, SPRING_MICRO); tap opens the ModeSwitcher (§3.4).
    private var modePill: some View {
        let mode = appState.activeMode
        return Button { appState.toggleSwitcher() } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: mode.colorHex))
                Text(mode.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(ZWColor.text1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(ZWColor.text3)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(ZWColor.surface2.opacity(0.8))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(ZWColor.separator, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(pillPulsing ? 1.15 : 1)
        .onChange(of: appState.modePulseTrigger) {
            pillPulsing = true
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                pillPulsing = false
            }
        }
    }

    /// §3.1 teleprompter (Main only, min-height 26): streaming partial words
    /// (17px/500, active word accent-blue, auto-scroll to end), teal shimmer
    /// while transcribing, final text after stop, else the idle hint.
    @ViewBuilder
    private var teleprompter: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch appState.phase {
            case .recording:
                VStack(alignment: .leading, spacing: 2) {
                    StreamingText(text: appState.partialText, highlightLastWord: true)
                    if appState.holdToTalkActive {
                        // §3.1 hold-to-talk caption
                        Text("Push to talk — release to paste")
                            .font(.system(size: 11))
                            .foregroundStyle(ZWColor.text2)
                    }
                }
            case .transcribing:
                ShimmerText(text: appState.partialText.isEmpty ? " " : appState.partialText, color: ZWColor.accentTeal)
                Text("Transcribing…")
                    .font(.system(size: 11))
                    .foregroundStyle(ZWColor.text2)
            case .pasting:
                StreamingText(text: appState.transcriptText, highlightLastWord: false)
            case .processing:
                // §3.1 processing: purple shimmer until tokens stream in; caption 11px/500 accent-purple
                if appState.processedText.isEmpty {
                    ShimmerText(text: appState.transcriptText.isEmpty ? " " : appState.transcriptText, color: ZWColor.accentPurple)
                } else {
                    StreamingText(text: appState.processedText, highlightLastWord: false)
                }
                Text("Processing with \(appState.activeMode.name) mode")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ZWColor.accentPurple)
            case .pasted:
                StreamingText(text: appState.transcriptText, highlightLastWord: false)
                // §3.1 pasted: green check + "Pasted to {app}", 11px/500 accent-green
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text(appState.pasteSubtitle)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(ZWColor.accentGreen)
            case .idle:
                if appState.micDenied {
                    hint("Microphone access is required to dictate.")
                } else if case let .downloading(fraction) = appState.modelStatus {
                    hint("Downloading speech model… \(Int(fraction * 100))%")
                } else if appState.modelStatus == .failed {
                    hint("Speech model failed to download — check your connection.")
                } else if appState.transcriptionFailed {
                    hint("Transcription failed — try again.")
                } else if appState.modeProcessingFailed {
                    // §8/§10.4: actionable failure, never a spinner
                    hint("\(appState.failedModeName) mode needs Apple Intelligence or a cloud key.")
                } else if !appState.transcriptText.isEmpty {
                    StreamingText(text: appState.transcriptText, highlightLastWord: false)
                } else {
                    hint("Tap the mic or hold right ⌘ to dictate.")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(ZWColor.text3)
            .lineLimit(1)
    }

    /// §3.1 bottom row. Idle: "Dismiss" ghost + "Start dictation" accent-red
    /// pill (or a "Grant microphone access" deep link per §8). Recording:
    /// Cancel ✕ (28×28 ghost) / center mode label / Stop ■ (28×28 accent-red).
    @ViewBuilder
    private var bottomRow: some View {
        if isRecording || isBusy {
            HStack {
                PopoverIconButton(systemName: "xmark", iconSize: 15, action: appState.cancel)
                    .help("Cancel dictation")
                Spacer(minLength: 0)
                if isMain {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                        Text(appState.activeMode.name)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(ZWColor.text3)
                }
                Spacer(minLength: 0)
                // Mini: stop button hidden until hover, slides x 24→0 (§3.1)
                PopoverIconButton(systemName: "square.fill", iconSize: 12, filled: true, action: appState.stopDictation)
                    .help("Stop dictation")
                    .opacity(isMain || hovering ? 1 : 0)
                    .offset(x: isMain || hovering ? 0 : 24)
            }
            .padding(.top, 4)
            .disabled(isBusy)
            .opacity(isBusy ? 0.4 : 1)
        } else {
            HStack {
                Button("Dismiss") { appState.dismissPopover() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ZWColor.text2)
                    .buttonStyle(ZWButtonStyle(hoverScale: 1.08, pressScale: 0.96))
                Spacer(minLength: 0)
                if appState.micDenied {
                    Button(action: openMicrophoneSettings) {
                        Label("Grant microphone access", systemImage: "mic")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ZWColor.accentBlue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(ZWButtonStyle())
                } else {
                    Button(action: appState.startDictation) {
                        Label("Start dictation", systemImage: "mic")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ZWColor.accentRed)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(ZWButtonStyle())
                }
            }
        }
    }

    private func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}

/// 28×28 popover control (§3.1 recording row): radius 6, hover surface-3 +
/// scale 1.08, press 0.97. `filled` renders the accent-red Stop variant.
private struct PopoverIconButton: View {
    let systemName: String
    let iconSize: CGFloat
    var filled = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize))
                .foregroundStyle(filled ? Color.white : ZWColor.text2)
                .frame(width: 28, height: 28)
                .background(filled ? ZWColor.accentRed : (hovering ? ZWColor.surface3 : .clear))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(ZWButtonStyle(hoverScale: 1.08, pressScale: 0.97))
        .onHover { hovering = $0 }
    }
}

/// §3.1 recording timer: 8px red dot pulsing (1s) + `m:ss.d` mono 11px text-2,
/// ticking at 50ms (spec §4.2).
private struct RecordingTimer: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.05)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            HStack(spacing: 6) {
                Circle()
                    .fill(ZWColor.accentRed)
                    .frame(width: 8, height: 8)
                    .opacity(0.65 + 0.35 * sin(2 * .pi * elapsed))
                Text(Self.format(elapsed))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ZWColor.text2)
            }
        }
    }

    /// Prototype `formatTimer`: `m:ss.d`.
    static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, remainder)
    }
}

/// §3.1 teleprompter line: single line, 17px/500, auto-scrolls to the end on
/// each update; the active (last) word renders accent-blue while recording.
private struct StreamingText: View {
    let text: String
    let highlightLastWord: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Text(attributed)
                    .font(.system(size: 17, weight: .medium))
                    .tracking(-0.17)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .id("streamingTextEnd")
            }
            .onChange(of: text) {
                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo("streamingTextEnd", anchor: .trailing)
                }
            }
        }
    }

    private var attributed: AttributedString {
        var attributed = AttributedString(text)
        if highlightLastWord, let lastSpace = text.lastIndex(of: " ") {
            let wordRange = text.index(after: lastSpace) ..< text.endIndex
            if let range = Range(wordRange, in: attributed) {
                attributed[range].foregroundColor = ZWColor.accentBlue
            }
        }
        return attributed
    }
}

/// §2.6 shimmer text: teal (transcribing) sweep, 1.2s linear.
private struct ShimmerText: View {
    let text: String
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            // §5.5 reduced motion: shimmer sweeps slowed to 3s
            let cycle = AppState.reduceMotion ? 3.0 : 1.2
            let elapsed = context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: cycle) / cycle
            let center = 1.4 - elapsed * 1.9 // sweep 1.4 → −0.5 per §2.6 (200% → −200% of 200%-size gradient)
            Text(text)
                .font(.system(size: 17, weight: .medium))
                .tracking(-0.17)
                .lineLimit(1)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: ZWColor.text1, location: max(0, min(1, center - 0.3))),
                            .init(color: color, location: max(0, min(1, center - 0.1))),
                            .init(color: ZWColor.text1, location: max(0, min(1, center + 0.1))),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}

/// §3.4 ModeSwitcher: 224px wide, radius 14, padding 6; rows with 14px icon in
/// mode color, 13px/500 label, mono kbd right; active row bg accent-blue/15
/// with a blue check (scale 0.5→1, SPRING_MICRO); hover surface-3/60.
struct ModeSwitcherView: View {
    let appState: AppState
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(appState.modes) { mode in
                ModeSwitcherRow(
                    mode: mode,
                    isActive: mode.id == appState.activeMode.id
                ) {
                    appState.setActiveMode(mode)
                    close()
                }
            }
        }
        .padding(6)
        .frame(width: 224)
    }
}

private struct ModeSwitcherRow: View {
    let mode: Mode
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: mode.colorHex))
                    .frame(width: 18)
                Text(mode.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ZWColor.text1)
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ZWColor.accentBlue)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else if let index = mode.shortcutIndex {
                    Text("⌘\(index)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ZWColor.text3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isActive ? ZWColor.accentBlue.opacity(0.15) : (hovering ? ZWColor.surface3.opacity(0.6) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isActive)
    }
}
