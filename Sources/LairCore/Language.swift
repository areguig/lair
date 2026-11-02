/// The languages an agent can speak; unset in the config means English.
public enum Language: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case french = "fr"

    /// How the language is named in its own words, so a picker reads the same whatever the screen's language.
    public var label: String {
        switch self {
        case .english: "English"
        case .french: "Français"
        }
    }

    /// What a voice says when you try it in Settings.
    public func introduction(of name: String) -> String {
        switch self {
        case .english: "Hi, I'm \(name)."
        case .french: "Bonjour, je suis \(name)."
        }
    }
}
