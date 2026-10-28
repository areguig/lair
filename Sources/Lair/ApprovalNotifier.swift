import LairCore
import UserNotifications

/// Shows an agent's approval request as a notification with Allow, Always Allow and Deny buttons.
@MainActor final class ApprovalNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "approval"
    private static let alwaysCategory = "approval-always"
    private static let allow = "allow"
    private static let always = "always"
    private static let deny = "deny"

    /// Called with the request id and the decision.
    var onAnswer: ((String, ApprovalDecision) -> Void)?

    func setUp() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let allow = UNNotificationAction(identifier: Self.allow, title: "Allow")
        let always = UNNotificationAction(identifier: Self.always, title: "Always Allow")
        let deny = UNNotificationAction(identifier: Self.deny, title: "Deny", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [allow, deny], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.alwaysCategory, actions: [allow, always, deny], intentIdentifiers: []),
        ])
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ request: ApprovalRequest, from agent: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(agent) needs your OK"
        content.body = request.summary
        content.subtitle = request.tool
        content.categoryIdentifier = request.canAlwaysAllow ? Self.alwaysCategory : Self.category
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
        let decision: ApprovalDecision? = switch response.actionIdentifier {
        case Self.allow: .allowOnce
        case Self.always: .allowAlways
        case Self.deny: .deny
        default: nil
        }
        guard let decision else { return }
        await MainActor.run { onAnswer?(id, decision) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
