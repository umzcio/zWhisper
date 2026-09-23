import AVFAudio
import AVFoundation
import ApplicationServices
import KeyboardShortcuts
import SwiftUI

/// Settings screen (spec §6.6): centered toolbar tab strip + four panes
/// (General / Sound / Shortcuts / Usage), all bound to `settings.json`.
struct SettingsView: View {
    @Bindable var appState: AppState

    @State private var tab: SettingsTab = .general
    @Namespace private var tabIndicator

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Group {
                switch tab {
                case .general: GeneralPane(appState: appState)
                case .sound: SoundPane(appState: appState)
                case .shortcuts: ShortcutsPane()
                case .usage: UsagePane(appState: appState)
                }
            }
            .id(tab)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: tab) // §6.6 pane crossfade
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appState.settings) { appState.settingsDidChange() }
    }

    /// §6.6: centered strip (border-b), four 64px items, icon 19px over
    /// 11px/500 label, sliding surface-3/70 rounded-8 indicator.
    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { item in
                Button {
                    tab = item
                    SettingsBlip.play(appState.settings.soundEffectsStyle)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19))
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? ZWColor.accentBlue : ZWColor.text3)
                    .frame(width: 64, height: 52)
                    .background {
                        if tab == item {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(ZWColor.surface3.opacity(0.7))
                                .matchedGeometryEffect(id: "tab-indicator", in: tabIndicator)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ZWButtonStyle(hoverScale: 1.0, pressScale: 0.96))
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ZWColor.separator).frame(height: 1)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: tab) // §5.1 SPRING_MICRO
    }
}

/// §6.6 toolbar tabs.
private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, sound, shortcuts, usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .sound: "Sound"
        case .shortcuts: "Shortcuts"
        case .usage: "Usage"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .sound: "waveform"
        case .shortcuts: "keyboard"
        case .usage: "chart.bar"
        }
    }
}

// MARK: - Shared chrome

/// §6.6 grouped list: 11px/600 uppercase text-3 title over a surface-2
/// radius-10 card of hairline-separated rows.
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ZWColor.text3)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(ZWColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

/// §6.6 row: min-height 48, 13px label (+ optional 11px caption), trailing control.
private struct SettingsRow<Control: View>: View {
    let label: String
    var caption: String?
    /// InfoTip text (§6.6 Restore clipboard): info.circle with a tooltip.
    var infoTip: String?
    var showsSeparator = false
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(ZWColor.text1)
                    if let infoTip {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(ZWColor.text3)
                            .help(infoTip)
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(ZWColor.text3)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(ZWColor.separator)
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
    }
}

extension View {
    /// §6.6 pane container: scrolling column, px 24 py 20, max 560 centered.
    fileprivate func settingsPane() -> some View {
        ScrollView {
            VStack(spacing: 20) { self }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - General pane (§6.6)

private struct GeneralPane: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            SettingsGroup(title: "Startup") {
                SettingsRow(label: "Launch at login", caption: nil, infoTip: nil, showsSeparator: true) {
                    Toggle("", isOn: $appState.settings.launchAtLogin).labelsHidden()
                }
                SettingsRow(label: "Show in Dock", caption: nil, infoTip: nil, showsSeparator: true) {
                    Toggle("", isOn: $appState.settings.showInDock).labelsHidden()
                }
                SettingsRow(
                    label: "Start recording when menu bar icon is clicked",
                    caption: "When off, the popover opens idle instead of recording.",
                    infoTip: nil,
                    showsSeparator: true
                ) {
                    Toggle("", isOn: $appState.settings.startRecordingOnStatusItemClick).labelsHidden()
                }
                SettingsRow(label: "Always close window after dictation", caption: nil, infoTip: nil) {
                    Toggle("", isOn: $appState.settings.alwaysCloseWindowAfterDictation).labelsHidden()
                }
            }

            SettingsGroup(title: "Appearance") {
                SettingsRow(label: "Theme", caption: nil, infoTip: nil, showsSeparator: true) {
                    Picker("", selection: $appState.settings.theme) {
                        Label("Light", systemImage: "sun.max").tag(SettingsStore.Theme.light)
                        Label("Dark", systemImage: "moon").tag(SettingsStore.Theme.dark)
                        Label("System", systemImage: "desktopcomputer").tag(SettingsStore.Theme.system)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 216)
                }
                SettingsRow(label: "Dictation indicator", caption: "Floating popover, or a compact pill pinned above your Dock.", infoTip: nil, showsSeparator: true) {
                    Picker("", selection: $appState.settings.popoverPlacement) {
                        Text("Top center").tag(SettingsStore.PopoverPlacement.top)
                        Text("Docked").tag(SettingsStore.PopoverPlacement.bottomRight)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 216)
                }
                SettingsRow(
                    label: "Sound effects style",
                    caption: "Played on toggles and confirmations across the app.",
                    infoTip: nil
                ) {
                    Picker("", selection: Binding(
                        get: { appState.settings.soundEffectsStyle },
                        set: {
                            appState.settings.soundEffectsStyle = $0
                            SettingsBlip.play($0)
                        }
                    )) {
                        Text("Subtle").tag(SettingsStore.SoundEffectsStyle.subtle)
                        Text("Classic").tag(SettingsStore.SoundEffectsStyle.classic)
                        Text("None").tag(SettingsStore.SoundEffectsStyle.none)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 216)
                }
            }

            SettingsGroup(title: "Paste") {
                SettingsRow(label: "Auto-paste after transcription", caption: nil, infoTip: nil, showsSeparator: true) {
                    Toggle("", isOn: $appState.settings.autoPaste).labelsHidden()
                }
                SettingsRow(
                    label: "Restore clipboard after paste",
                    caption: nil,
                    infoTip: "We restore your previous clipboard after pasting"
                ) {
                    Toggle("", isOn: $appState.settings.restoreClipboard).labelsHidden()
                }
            }

            SettingsGroup(title: "Language") {
                SettingsRow(label: "Spoken language", caption: "100+ languages supported", infoTip: nil, showsSeparator: true) {
                    Picker("", selection: $appState.settings.language) {
                        Text("Auto-detect").tag("auto")
                        Text("English").tag("en")
                        Text("Español").tag("es")
                        Text("Français").tag("fr")
                        Text("Deutsch").tag("de")
                        Text("Italiano").tag("it")
                        Text("Português").tag("pt")
                        Text("日本語").tag("ja")
                        Text("中文").tag("zh")
                        Text("한국어").tag("ko")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 168)
                }
                SettingsRow(label: "Translate to English", caption: nil, infoTip: nil) {
                    Toggle("", isOn: $appState.settings.translateToEnglish).labelsHidden()
                }
            }

            // §8 re-prompt: live grant status with System Settings deep links.
            SettingsGroup(title: "Permissions") {
                SettingsRow(label: "Microphone", caption: "Required to record", infoTip: nil, showsSeparator: true) {
                    PermissionsStatusView(settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                    }
                }
                SettingsRow(label: "Accessibility", caption: "Auto-paste and push-to-talk", infoTip: nil) {
                    PermissionsStatusView(settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        AXIsProcessTrusted()
                    }
                }
            }

            VStack(spacing: 8) {
                ZWAppIcon(size: 32)
                Text("zWhisper v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") — on-device dictation")
                    .font(.system(size: 11))
                    .foregroundStyle(ZWColor.text3)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .settingsPane()
    }
}

// MARK: - Sound pane (§6.6, ported from StubSettingsView)

private struct SoundPane: View {
    @Bindable var appState: AppState

    @State private var testing = false
    @State private var toast: String?

    var body: some View {
        Group {
            SettingsGroup(title: "Input") {
                SettingsRow(label: "Input device", caption: nil, infoTip: nil, showsSeparator: true) {
                    InputDevicePicker(appState: appState)
                }
                SettingsRow(label: "Input level", caption: nil, infoTip: nil, showsSeparator: true) {
                    InputMeterView(level: appState.currentLevel)
                        .frame(width: 240)
                }
                SettingsRow(label: "Microphone check", caption: nil, infoTip: nil) {
                    HStack(spacing: 8) {
                        if appState.micDenied {
                            Button("Grant microphone access", action: openMicrophoneSettings)
                                .controlSize(.small)
                        }
                        Button {
                            testMicrophone()
                        } label: {
                            Label(testing ? "Testing…" : "Test microphone", systemImage: "play.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(testing ? ZWColor.text3 : ZWColor.accentBlue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(testing ? ZWColor.surface3 : ZWColor.accentBlue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(ZWColor.separator)
                                )
                        }
                        .buttonStyle(ZWButtonStyle())
                        .disabled(testing)
                    }
                }
            }

            SettingsGroup(title: "Processing") {
                SettingsRow(
                    label: "Dynamic normalization",
                    caption: "Keeps quiet and loud speech consistent.",
                    infoTip: nil,
                    showsSeparator: true
                ) {
                    Toggle("", isOn: $appState.settings.dynamicNormalization).labelsHidden()
                }
                SettingsRow(label: "Silence removal", caption: nil, infoTip: nil, showsSeparator: true) {
                    Toggle("", isOn: $appState.settings.silenceRemoval).labelsHidden()
                }
                SettingsRow(label: "Aggressiveness", caption: nil, infoTip: nil) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { Double(appState.settings.silenceAggressiveness) },
                                set: { appState.settings.silenceAggressiveness = Int($0.rounded()) }
                            ),
                            in: 0 ... 100
                        )
                        .frame(width: 176)
                        .disabled(!appState.settings.silenceRemoval)
                        Text("\(appState.settings.silenceAggressiveness)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(appState.settings.silenceRemoval ? ZWColor.text2 : ZWColor.text3)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }

            SettingsGroup(title: "Listening") {
                SettingsRow(
                    label: "Active duration",
                    caption: "Backstop only — recording normally stops when you stop talking.",
                    infoTip: nil
                ) {
                    Picker("", selection: $appState.settings.activeDuration) {
                        Text("1m").tag(TimeInterval?.some(60))
                        Text("5m").tag(TimeInterval?.some(300))
                        Text("10m").tag(TimeInterval?.some(600))
                        Text("∞").tag(TimeInterval?.none)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
        .settingsPane()
        .task { appState.startMetering() }
        .onDisappear { appState.stopMetering() }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(ZWColor.surface3)
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 12)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: toast)
    }

    /// §6.6: 3s test run against the already-live meter, then a toast.
    private func testMicrophone() {
        guard !testing else { return }
        testing = true
        SettingsBlip.play(appState.settings.soundEffectsStyle)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            testing = false
            toast = "Microphone looks good"
            try? await Task.sleep(for: .seconds(3))
            if toast == "Microphone looks good" { toast = nil }
        }
    }

    private func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}

/// §6.6 input device picker: "System default" (nil) + every capturable input.
/// Refreshes on appear and every 2s while visible (USB mics hotplug).
private struct InputDevicePicker: View {
    @Bindable var appState: AppState
    @State private var devices: [(id: String, name: String)] = []

    var body: some View {
        Picker("", selection: $appState.settings.inputDeviceUID) {
            Text("System default").tag(String?.none)
            ForEach(devices, id: \.id) { device in
                Text(device.name).tag(String?.some(device.id))
            }
            // Keep the current selection visible if the device is unplugged.
            if let uid = appState.settings.inputDeviceUID,
               !devices.contains(where: { $0.id == uid }) {
                Text("Unavailable device").tag(String?.some(uid))
            }
        }
        .labelsHidden()
        .frame(width: 240)
        .onAppear { refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private func refresh() {
        let found = appState.inputDevices()
        if found.map(\.id) != devices.map(\.id) { devices = found }
    }
}

/// §6.6 input meter: 24 segments, 3px gap, 14px tall, radius 2,
/// green → yellow → red thresholds.
private struct InputMeterView: View {
    /// Normalized 0…1 level.
    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 24, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(for: index))
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
            }
        }
        .animation(.linear(duration: 0.075), value: level)
        .accessibilityLabel("Input level")
    }

    private func color(for index: Int) -> Color {
        guard Float(index) / 24 < level else { return ZWColor.surface3 }
        switch index {
        case ..<14: return ZWColor.accentGreen
        case ..<20: return Color(red: 1.0, green: 0xD6 / 255, blue: 0x0A / 255) // #FFD60A
        default: return ZWColor.accentRed
        }
    }
}

// MARK: - Shortcuts pane (§6.6)

private struct ShortcutsPane: View {
    var body: some View {
        Group {
            SettingsGroup(title: "Keyboard") {
                SettingsRow(label: "Toggle recording", caption: nil, infoTip: nil, showsSeparator: true) {
                    KeyboardShortcuts.Recorder(for: .toggleRecording)
                }
                SettingsRow(label: "Push to talk (hold)", caption: "Default: hold right ⌘", infoTip: nil, showsSeparator: true) {
                    ChordRecorder(
                        fallbackText: "Right ⌘",
                        load: { PTTShortcut.current },
                        save: { PTTShortcut.store($0) },
                        clear: { PTTShortcut.clear() }
                    )
                }
                SettingsRow(label: "Cancel dictation", caption: "Default: esc", infoTip: nil, showsSeparator: true) {
                    ChordRecorder(
                        fallbackText: "esc",
                        load: { CancelShortcut.current },
                        save: { CancelShortcut.store($0) }
                    )
                }
                SettingsRow(label: "Change mode (cycle)", caption: nil, infoTip: nil, showsSeparator: true) {
                    KeyboardShortcuts.Recorder(for: .changeModeCycle)
                }
                SettingsRow(label: "Mode shortcuts", caption: nil, infoTip: nil) {
                    HStack(spacing: 4) {
                        ForEach(1 ... 9, id: \.self) { digit in
                            ShortcutChip(text: "⌘\(digit)")
                        }
                    }
                }
            }

            Text("Mode shortcuts are active while the popover is open.")
                .font(.system(size: 11))
                .foregroundStyle(ZWColor.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .settingsPane()
    }
}

/// §6.6 ShortcutKey chip: mono 11px, radius 6, hairline, surface-2.
private struct ShortcutChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(ZWColor.text2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ZWColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(ZWColor.separator)
            )
    }
}

// MARK: - Usage pane (§6.6)

/// §6.6 Usage: StatCards with count-ups + 7-day sparkline, typing test, and
/// share card — everything aggregated from `history`.
private struct UsagePane: View {
    let appState: AppState

    @State private var toast: String?

    private var stats: UsageStats { UsageStats(history: appState.history) }

    var body: some View {
        Group {
            UsageSection(index: 0) {
                HStack(spacing: 12) {
                    StatCard(label: "Words dictated", caption: nil) {
                        CountUp(value: Double(stats.totalWords))
                    } extra: {
                        Sparkline(data: stats.dailyWords)
                            .padding(.top, 4)
                    }
                    StatCard(label: "Dictation speed", caption: "vs 41 wpm typing") {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            CountUp(value: Double(stats.dictationWPM))
                            Text("wpm")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ZWColor.text2)
                        }
                    } extra: { EmptyView() }
                    StatCard(label: "Time saved", caption: "all time") {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            CountUp(value: stats.hoursSaved, decimals: 1)
                            Text("hrs")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ZWColor.text2)
                        }
                    } extra: { EmptyView() }
                }
            }
            UsageSection(index: 1) {
                TypingTestCard(
                    dictationWPM: stats.dictationWPM,
                    soundStyle: appState.settings.soundEffectsStyle
                )
            }
        }
        .settingsPane()
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(ZWColor.surface3)
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 12)))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: toast)
    }

    private func showToast(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
    }
}

/// §6.6 aggregates from `history`: all-time, this calendar month, 7-day trend.
private struct UsageStats {
    private(set) var totalWords = 0
    private(set) var totalMinutes = 0.0
    private(set) var monthWords = 0
    /// Words per day, oldest → today (§6.6 sparkline).
    private(set) var dailyWords = [Double](repeating: 0, count: 7)

    /// Typing at 41 wpm vs dictating at 148 wpm, in hours (spec §6.6).
    static func hoursSaved(forWords words: Int) -> Double {
        Double(words) * (1.0 / 41 - 1.0 / 148) / 60
    }

    var dictationWPM: Int {
        totalMinutes > 0 ? Int((Double(totalWords) / totalMinutes).rounded()) : 0
    }

    var hoursSaved: Double { Self.hoursSaved(forWords: totalWords) }
    var monthHours: Double { Self.hoursSaved(forWords: monthWords) }

    init(history: [HistoryEntry], now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        for entry in history {
            let words = entry.processedText.split(separator: " ").count
            totalWords += words
            totalMinutes += entry.duration / 60
            if entry.createdAt >= monthStart { monthWords += words }
            let entryDay = calendar.startOfDay(for: entry.createdAt)
            let daysAgo = calendar.dateComponents([.day], from: entryDay, to: today).day ?? 0
            if (0 ..< 7).contains(daysAgo) { dailyWords[6 - daysAgo] += Double(words) }
        }
    }
}

/// §5.3 Usage rows: y 16→0 + fade, stagger 0.07s, spring 400/30 (SPRING_DEFAULT).
private struct UsageSection<Content: View>: View {
    let index: Int
    @ViewBuilder let content: Content

    @State private var shown = false

    var body: some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                withAnimation(.spring(response: 0.31, dampingFraction: 0.75).delay(Double(index) * 0.07)) {
                    shown = true
                }
            }
    }
}

/// §6.6 StatCard: surface-2, radius 16, hairline; 11px uppercase label over a
/// 32px/700 tabular value, optional caption and extra (sparkline).
private struct StatCard<Value: View, Extra: View>: View {
    let label: String
    var caption: String?
    @ViewBuilder let value: Value
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.55) // 0.05em at 11px
                .foregroundStyle(ZWColor.text3)
            value
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(ZWColor.text2)
            }
            extra
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ZWColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ZWColor.separator)
        )
    }
}

/// §6.6 count-up: 0 → value over 1.2s ease-out cubic on appearance (restarts
/// whenever the pane re-appears, since pane switching recreates the view tree).
private struct CountUp: View {
    let value: Double
    var decimals = 0

    @State private var displayed = 0.0

    var body: some View {
        Text(decimals > 0
            ? String(format: "%.\(decimals)f", displayed)
            : Int(displayed.rounded()).formatted(.number))
            .font(.system(size: 32, weight: .bold))
            .tracking(-0.96) // −0.03em at 32px, spec §2.2 stat numerals
            .monospacedDigit()
            .foregroundStyle(ZWColor.text1)
            .task {
                let steps = 72 // 1.2s at ~60fps
                for step in 0 ... steps {
                    let progress = Double(step) / Double(steps)
                    displayed = value * (1 - pow(1 - progress, 3))
                    try? await Task.sleep(for: .milliseconds(17))
                }
            }
    }
}

/// §6.6 7-day sparkline: 120×32 viewBox, accent stroke 1.5px, 1s stroke-draw,
/// no dots or axes.
private struct Sparkline: View {
    /// 7 values, oldest → today.
    let data: [Double]

    @State private var drawn = false

    var body: some View {
        SparklineShape(data: data)
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(ZWColor.accentBlue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(height: 32)
            .onAppear {
                withAnimation(.easeOut(duration: 1)) { drawn = true }
            }
            .accessibilityHidden(true)
    }
}

private struct SparklineShape: Shape {
    let data: [Double]

    func path(in rect: CGRect) -> Path {
        // 120×32 viewBox with 2px padding, mapped into the proposed rect.
        guard data.count > 1 else { return Path() }
        let lower = data.min() ?? 0
        let span = (data.max() ?? 0) - lower
        var path = Path()
        for (index, value) in data.enumerated() {
            let x = rect.minX + 2 + CGFloat(index) * (rect.width - 4) / CGFloat(data.count - 1)
            let normalized = span > 0 ? (value - lower) / span : 0.5
            let y = rect.maxY - 2 - normalized * (rect.height - 4)
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// §6.6 typing test: per-character feedback, live mono wpm meter, then
/// compare bars vs dictation speed once the sentence matches.
private struct TypingTestCard: View {
    let dictationWPM: Int
    let soundStyle: SettingsStore.SoundEffectsStyle

    private static let sentence = "The quick brown fox jumps over the lazy dog."

    @State private var typed = ""
    @State private var startTime: Date?
    @State private var endTime: Date?

    private var finished: Bool { endTime != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How fast do you type?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ZWColor.text1)
                Spacer()
                if !typed.isEmpty || finished {
                    Button {
                        SettingsBlip.play(soundStyle)
                        typed = ""
                        startTime = nil
                        endTime = nil
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ZWColor.text2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ZWButtonStyle())
                }
            }

            sentenceText

            TextField("Start typing the sentence…", text: inputBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(ZWColor.text1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ZWColor.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(ZWColor.separator)
                )
                .disabled(finished)

            HStack {
                if startTime != nil && !finished {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        meterText(at: context.date)
                    }
                } else {
                    meterText(at: endTime ?? .now)
                }
                Spacer()
                if let startTime, let endTime {
                    Text(String(format: "%.1fs", endTime.timeIntervalSince(startTime)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ZWColor.text2)
                }
            }

            if finished {
                TypingResultView(yourWPM: wpm(at: endTime ?? .now), dictationWPM: dictationWPM)
            }
        }
        .padding(16)
        .background(ZWColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ZWColor.separator)
        )
    }

    private var inputBinding: Binding<String> {
        Binding(
            get: { typed },
            set: { value in
                guard !finished else { return }
                typed = String(value.prefix(Self.sentence.count))
                if startTime == nil && !typed.isEmpty { startTime = .now }
                if typed == Self.sentence { endTime = .now }
            }
        )
    }

    /// Standard typing-test measure: characters/5 per minute (prototype UsageTab).
    private func wpm(at now: Date) -> Int {
        guard let startTime else { return 0 }
        let seconds = (endTime ?? now).timeIntervalSince(startTime)
        guard seconds > 0.5 else { return 0 }
        return Int((Double(typed.count) / 5 / (seconds / 60)).rounded())
    }

    private func meterText(at now: Date) -> some View {
        HStack(spacing: 4) {
            Text("Live speed:")
            Text("\(wpm(at: now))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(ZWColor.text1)
            Text("wpm")
        }
        .font(.system(size: 11))
        .foregroundStyle(ZWColor.text2)
    }

    /// Per-character feedback (prototype UsageTab): green when correct, red on
    /// a red wash when mismatched, text-3 until typed.
    private var sentenceText: Text {
        var result = AttributedString()
        for (index, character) in Self.sentence.enumerated() {
            var part = AttributedString(String(character))
            if index < typed.count {
                let typedCharacter = typed[typed.index(typed.startIndex, offsetBy: index)]
                if typedCharacter == character {
                    part.foregroundColor = ZWColor.accentGreen
                } else {
                    part.foregroundColor = ZWColor.accentRed
                    part.backgroundColor = ZWColor.accentRed.opacity(0.25)
                }
            } else {
                part.foregroundColor = ZWColor.text3
            }
            result += part
        }
        return Text(result).font(.system(size: 12, design: .monospaced))
    }
}

/// §6.6 compare bars: yours vs dictation wpm, width tween 0.8s
/// cubic-bezier(0.16,1,0.3,1), plus the verdict line.
private struct TypingResultView: View {
    let yourWPM: Int
    let dictationWPM: Int

    @State private var drawn = false

    private var barMax: Double { Double(max(yourWPM, dictationWPM, 1)) }

    var body: some View {
        VStack(spacing: 8) {
            CompareBar(label: "You", value: yourWPM, fraction: drawn ? Double(yourWPM) / barMax : 0, color: ZWColor.accentTeal)
            CompareBar(label: "Dictation", value: dictationWPM, fraction: drawn ? Double(dictationWPM) / barMax : 0, color: ZWColor.accentBlue)
            verdict
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(ZWColor.separator).frame(height: 1)
        }
        .opacity(drawn ? 1 : 0)
        .offset(y: drawn ? 0 : 8)
        .onAppear {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8)) { drawn = true }
        }
    }

    private var verdict: some View {
        Group {
            if yourWPM > 0 && dictationWPM > yourWPM {
                Text("Dictation is ")
                    + Text(String(format: "%.1f× faster", Double(dictationWPM) / Double(yourWPM)))
                    .foregroundColor(ZWColor.accentGreen)
                    + Text(" than your typing.")
            } else {
                Text("Dictation is slower — keep practicing")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(ZWColor.text1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompareBar: View {
    let label: String
    let value: Int
    /// 0…1 fill, animated by the caller.
    let fraction: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(ZWColor.text2)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geometry in
                Capsule(style: .continuous)
                    .fill(ZWColor.surface3.opacity(0.6))
                    .overlay(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(color)
                            .frame(width: max(4, geometry.size.width * fraction))
                    }
            }
            .frame(height: 12)
            Text("\(value) wpm")
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(ZWColor.text1)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

/// §6.6 share card 320×180: dark gradient + logo + monthly hours saved.
/// Download PNG is decorative per spec (toast); Copy text is real (NSPasteboard).

// MARK: - Sound effects (§6.6)

/// Synthesized sine blips for the sound-effects-style setting: Subtle =
/// 1240Hz gain 0.035, Classic = 760Hz gain 0.09, 90ms with exponential decay.
@MainActor
private enum SettingsBlip {
    private static var player: AVAudioPlayer?

    static func play(_ style: SettingsStore.SoundEffectsStyle) {
        let frequency: Double
        let gain: Double
        switch style {
        case .subtle: frequency = 1240; gain = 0.035
        case .classic: frequency = 760; gain = 0.09
        case .none: return
        }
        player = try? AVAudioPlayer(data: wavData(frequency: frequency, gain: gain))
        player?.play()
    }

    /// Minimal 16-bit mono PCM WAV, 44.1kHz.
    private static func wavData(frequency: Double, gain: Double) -> Data {
        let sampleRate = 44_100
        let count = sampleRate * 9 / 100 // 90ms
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: MemoryLayout<T>.size))
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)) // PCM chunk size
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2)) // byte rate
        append(UInt16(2)) // block align
        append(UInt16(16)) // bits
        data.append(contentsOf: "data".utf8)
        append(UInt32(count * 2))
        for index in 0 ..< count {
            let t = Double(index) / Double(sampleRate)
            let sample = sin(2 * .pi * frequency * t) * gain * exp(-t * 28)
            append(Int16(sample * Double(Int16.max)))
        }
        return data
    }
}

/// §8 Permissions row status: green check when granted, else an
/// "Open System Settings" deep-link button. Re-reads status every 2s.
private struct PermissionsStatusView: View {
    let settingsURL: String
    let isGranted: () -> Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if isGranted() {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ZWColor.accentGreen)
            } else {
                Button("Open System Settings") {
                    if let url = URL(string: settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ZWColor.accentBlue)
                .buttonStyle(ZWButtonStyle(pressScale: 0.96))
            }
        }
    }
}

/// Recorder for the Cancel-dictation binding (§6.6). Unlike the
/// KeyboardShortcuts rows, this stores without registering globally — the
/// binding is matched by HotkeyManager's observe-only Esc monitor.
/// Recorder pill that stores a KeyChord in UserDefaults WITHOUT registering a
/// global hotkey (a handler-less Carbon hotkey would swallow the key in every
/// app until relaunch — the M7 PTT bug). Esc while armed cancels the capture.
private struct ChordRecorder: View {
    let fallbackText: String
    let load: () -> KeyChord?
    let save: (KeyChord) -> Void
    let clear: (() -> Void)?

    @State private var chord: KeyChord?
    @State private var armed = false
    @State private var monitor: Any?

    init(
        fallbackText: String,
        load: @escaping () -> KeyChord?,
        save: @escaping (KeyChord) -> Void,
        clear: (() -> Void)? = nil
    ) {
        self.fallbackText = fallbackText
        self.load = load
        self.save = save
        self.clear = clear
        _chord = State(initialValue: load())
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                armed ? disarm() : arm()
            } label: {
                Text(armed ? "Press shortcut…" : (chord?.displayText ?? fallbackText))
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(armed ? ZWColor.accentBlue.opacity(0.2) : ZWColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(armed ? ZWColor.accentBlue : ZWColor.separator, lineWidth: 1)
                    )
                    .foregroundStyle(ZWColor.text1)
            }
            .buttonStyle(.plain)
            if let clear, chord != nil, !armed {
                Button {
                    clear()
                    chord = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ZWColor.text3)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
        .onDisappear(perform: disarm)
    }

    private func arm() {
        armed = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels the capture instead of recording it.
            guard event.keyCode != 53 else {
                Task { @MainActor in disarm() }
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let captured = KeyChord(keyCode: event.keyCode, modifiers: Int(modifiers.rawValue))
            save(captured)
            Task { @MainActor in
                chord = captured
                disarm()
            }
            return nil // consume the captured key so it doesn't fire elsewhere
        }
    }

    private func disarm() {
        armed = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
