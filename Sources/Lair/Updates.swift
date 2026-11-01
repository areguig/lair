import LairCore
import Observation
import Sparkle

/// Sparkle with gentle reminders: a scheduled check opens no window, the panel and menu-bar icon show `reminder`.
@Observable @MainActor final class Updates: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private(set) var reminder = UpdateReminder()
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func install() {
        controller?.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        reminder.found(update.displayVersionString, userInitiated: state.userInitiated)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        reminder.seen()
    }

    func standardUserDriverWillFinishUpdateSession() {
        reminder.seen()
    }
}
