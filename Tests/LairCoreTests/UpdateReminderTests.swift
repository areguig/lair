import LairCore
import Testing

struct UpdateReminderTests {
    @Test func anUpdateFoundInTheBackgroundWaits() {
        var reminder = UpdateReminder()
        reminder.found("0.2.2", userInitiated: false)
        #expect(reminder.version == "0.2.2")
    }

    @Test func anUpdateYouAskedForDoesNotWaitSinceItsWindowIsOpen() {
        var reminder = UpdateReminder()
        reminder.found("0.2.2", userInitiated: true)
        #expect(reminder.version == nil)
    }

    @Test func lookingAtTheUpdateClearsIt() {
        var reminder = UpdateReminder()
        reminder.found("0.2.2", userInitiated: false)
        reminder.seen()
        #expect(reminder.version == nil)
    }
}
