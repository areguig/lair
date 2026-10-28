import LairCore
import UserNotifications

/// Shows an agent's approval request as a notification with Allow and Deny buttons.
@MainActor final class ApprovalNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "approval"
    private static let allow = "allow"
    private static let deny = "deny"

    /// Called with the request id and the answer.
    var onAnswer: ((String, Bool) -> Void)?

    func setUp() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(
            identifier: Self.category,
            actions: [UNNotificationAction(identifier: Self.allow, title: "Allow"),
                      UNNotificationAction(identifier: Self.deny, title: "Deny", options: [.destructive])],
            intentIdentifiers: [])])
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ request: ApprovalRequest, from agent: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(agent) needs your OK"
        content.body = request.summary
        content.subtitle = request.tool
        content.categoryIdentifier = Self.category
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: request.id, content: content, trigger: nil))
    }

    func remove(_ requestID: String) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        // Tapping the notification itself is not an answer.
        let allow: Bool? = switch response.actionIdentifier {
        case Self.allow: true
        case Self.deny: false
        default: nil
        }
        guard let allow else { return }
        await MainActor.run { onAnswer?(id, allow) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
