import Sparkle

/// Sparkle auto-updates for the direct-distribution build (architecture §2).
/// Excluded from any Mac App Store build (§10.6).
@MainActor
enum UpdateController {
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
