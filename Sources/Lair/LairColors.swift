import SwiftUI

/// What a color means, the same on every screen. An agent's own color shows the agent at work; these are about you.
enum LairColors {
    /// You're needed: an approval or a question.
    static let attention = Color.orange
    /// Something went wrong.
    static let problem = Color.red
    /// The agent said something while you were elsewhere.
    static let unread = Color.blue
    static let call = Color.green
    static let hangUp = Color.red
}
