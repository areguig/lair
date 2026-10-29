import LairCore
import UserNotifications

/// Shows an agent's approval request as a notification with Allow, Always Allow and Deny buttons,
/// and a guest's question with a field to answer it.
@MainActor final class ApprovalNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "approval"
    private static let alwaysCategory = "approval-always"
    private static let allow = "allow"
    private static let always = "always"
    private static let deny = "deny"
    private static let question = "question"
    private static let reply = "reply"
    /// A choice button's action id ends with its index.
    private nonisolated static let choice = "choice-"
    /// The choices of each question on screen, by call id, to turn a button back into its text.
    private var choices: [String: [String]] = [:]

    /// Called with the request id and the decision.
    var onAnswer: ((String, ApprovalDecision) -> Void)?
    /// Called with the request id when the notification itself is clicked.
    var onOpen: ((String) -> Void)?
    /// Called with the asking call's id and what you typed.
    var onReply: ((String, String) -> Void)?

    func setUp() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let allow = UNNotificationAction(identifier: Self.allow, title: "Allow")
        let always = UNNotificationAction(identifier: Self.always, title: "Always Allow")
        let deny = UNNotificationAction(identifier: Self.deny, title: "Deny", options: [.destructive])
        fixed = [
            UNNotificationCategory(identifier: Self.category, actions: [allow, deny], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.alwaysCategory, actions: [allow, always, deny], intentIdentifiers: []),
            Self.questionCategory(id: Self.question, choices: []),
        ]
        center.setNotificationCategories(Set(fixed))
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private var fixed: [UNNotificationCategory] = []

    /// A button per choice, then a field for anything else.
    private static func questionCategory(id: String, choices: [String]) -> UNNotificationCategory {
        let buttons = choices.prefix(4).enumerated().map { UNNotificationAction(identifier: choice + "\($0)", title: $1) }
        let field = UNTextInputNotificationAction(identifier: reply, title: choices.isEmpty ? "Answer" : "Something else…",
                                                  options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Your answer")
        return UNNotificationCategory(identifier: id, actions: buttons + [field], intentIdentifiers: [])
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

    /// A guest's question, answered by typing in the notification; `id` is the asking call's.
    func postQuestion(_ question: String, choices: [String], id: String, from agent: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(agent) asks"
        content.body = question
        content.categoryIdentifier = Self.question
        if !choices.isEmpty {
            // Categories are fixed per notification, so each question with choices gets its own.
            self.choices[id] = choices
            let category = Self.questionCategory(id: Self.question + "-" + id, choices: choices)
            let others = self.choices.keys.map { Self.questionCategory(id: Self.question + "-" + $0, choices: self.choices[$0]!) }
            UNUserNotificationCenter.current().setNotificationCategories(Set(fixed + others + [category]))
            content.categoryIdentifier = category.identifier
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func remove(_ requestID: String) {
        choices[requestID] = nil
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        if let reply = response as? UNTextInputNotificationResponse {
            let text = reply.userText
            return await MainActor.run { onReply?(id, text) }
        }
        let action = response.actionIdentifier
        if action.hasPrefix(Self.choice), let index = Int(action.dropFirst(Self.choice.count)) {
            return await MainActor.run {
                guard let picked = choices[id], picked.indices.contains(index) else { return }
                onReply?(id, picked[index])
            }
        }
        let decision: ApprovalDecision? = switch response.actionIdentifier {
        case Self.allow: .allowOnce
        case Self.always: .allowAlways
        case Self.deny: .deny
        default: nil
        }
        // Clicking the notification itself is not an answer: it brings that agent into focus.
        await MainActor.run {
            if let decision { onAnswer?(id, decision) } else { onOpen?(id) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
