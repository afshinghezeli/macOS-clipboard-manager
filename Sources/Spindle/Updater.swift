import Foundation
import Sparkle
import SpindleUI

/// Checks for and installs updates with Sparkle, when the build is set up for it: a release build
/// with a feed URL and a public key in Info.plist. Debug builds never update themselves.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let settings: Settings
    private var controller: SPUStandardUpdaterController?

    /// An update was found in the background and is waiting for the user to look at it.
    private(set) var isUpdatePending = false {
        didSet { if isUpdatePending != oldValue { onPendingUpdateChange?(isUpdatePending) } }
    }
    var onPendingUpdateChange: ((Bool) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        guard info["SUFeedURL"] != nil, info["SUPublicEDKey"] != nil else { return }
        // Sparkle asks before the first automatic check, so update checks, the only network
        // traffic Spindle ever causes, happen only with the user's consent.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    /// The controls for the settings window; `nil` when this build doesn't update itself.
    var controls: UpdateControls? {
        guard let updater = controller?.updater else { return nil }
        return UpdateControls(
            automaticallyChecks: { updater.automaticallyChecksForUpdates },
            setAutomaticallyChecks: { updater.automaticallyChecksForUpdates = $0 },
            checkNow: { [weak self] in self?.checkForUpdates() })
    }

    /// Checks now, or brings a pending update to the front.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // Sparkle calls its delegates on the main thread.

    // Betas are appcast items on Sparkle's "beta" channel; everyone gets the default channel.
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated { settings.receivesBetaUpdates ? ["beta"] : [] }
    }

    // MARK: - Gentle reminders

    // A menu bar app is almost never the active app, so an update window opened by a background
    // check would appear behind whatever the user is doing. Sparkle shows it right away only when
    // Spindle has focus (just launched); otherwise the menu bar icon gets a dot and the menu an
    // "Update Available…" item.

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        MainActor.assumeIsolated { isUpdatePending = true }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { isUpdatePending = false }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { isUpdatePending = false }
    }
}
