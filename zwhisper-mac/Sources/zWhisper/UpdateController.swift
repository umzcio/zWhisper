import AppKit
import Observation
import Sparkle

/// Sparkle auto-updates for the direct-distribution build (architecture §2).
/// Excluded from any Mac App Store build (§10.6). Started at launch so
/// scheduled checks run; Settings → About binds to the observed state.
@MainActor
@Observable
final class UpdateController {
    static let shared = UpdateController()

    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    private(set) var automaticallyChecksForUpdates = false

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private init() {
        let updater = controller.updater
        let refresh: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        observations = [
            updater.observe(\.canCheckForUpdates) { _, _ in refresh() },
            updater.observe(\.lastUpdateCheckDate) { _, _ in refresh() },
            updater.observe(\.automaticallyChecksForUpdates) { _, _ in refresh() },
        ]
        refresh()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    private func refresh() {
        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }
}
