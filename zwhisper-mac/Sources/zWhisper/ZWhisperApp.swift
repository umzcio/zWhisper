import SwiftUI

@main
struct ZWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let appState = AppState()

    init() {
        appDelegate.appState = appState
    }

    var body: some Scene {
        // Menu-bar agent (LSUIElement): the Settings scene supplies a minimal
        // main menu (architecture §2) and hosts the openWindow bridge for
        // WindowActions (its view renders at launch, so the bridge is always set).
        Settings {
            Text("zWhisper")
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onAppear {
                    WindowActions.openWindow = openWindow
                }
        }

        WindowGroup("zWhisper", id: "manage") {
            ManagementView(appState: appState)
        }
        .windowResizability(.contentSize)

        // First-run onboarding (architecture §8); single-instance Window scene.
        Window("Welcome to zWhisper", id: "onboarding") {
            OnboardingView(appState: appState) {
                dismissWindow(id: "onboarding")
            }
        }
        .windowResizability(.contentSize)
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    private var statusItemController: StatusItemController?
    private var popoverController: PopoverController?
    private var toastController: ToastController?
    private var modeSwitcherController: ModeSwitcherController?
    private let hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let appState else { return }
        let needsOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let popover = PopoverController(appState: appState)
        appState.popover = popover
        popoverController = popover

        let toast = ToastController()
        appState.toast = toast
        toastController = toast

        let switcher = ModeSwitcherController(appState: appState)
        appState.switcher = switcher
        modeSwitcherController = switcher
        WindowActions.appState = appState

        statusItemController = StatusItemController {
            appState.statusItemClicked()
        }
        appState.setModeDigitsEnabled = { [hotkeyManager] enabled in
            hotkeyManager.setModeDigitsEnabled(enabled)
        }
        appState.setEscapeHotkeyEnabled = { [hotkeyManager] enabled in
            hotkeyManager.setCancelDictationEnabled(enabled)
        }
        hotkeyManager.setUp(
            onToggleRecording: { appState.toggleDictation() },
            onCancel: { appState.cancel() },
            onCycleMode: { appState.cycleMode() },
            onModeDigit: { appState.switchMode(shortcutIndex: $0) }
        )
        hotkeyManager.setUpPushToTalk(
            onStart: { appState.startPushToTalk() },
            onStop: { appState.stopPushToTalk() }
        )
        Task {
            await appState.loadSettings()
            await appState.loadModes()
            await appState.loadHistory()
            // Onboarding owns the default-model download on first run (§8);
            // OnboardingView calls prepareTranscription() when it finishes.
            if !needsOnboarding {
                await appState.prepareTranscription()
            }
        }
        if needsOnboarding {
            Task { @MainActor in
                // The Settings scene's 1px view installs the openWindow bridge
                // on appear — wait briefly for it before presenting.
                for _ in 0 ..< 40 {
                    if WindowActions.openWindow != nil { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                if WindowActions.openWindow != nil {
                    WindowActions.openWindow?(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    // No bridge: skip the window rather than leave the model unloaded.
                    await appState.prepareTranscription()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await appState?.flushPersistence() }
    }
}
