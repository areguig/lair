import Foundation

/// The voices an agent can have, per language: Kyutai's Pocket TTS voices whose licence allows shipping them (CC BY 4.0 or CC0).
public enum Voices {
    public struct Voice: Equatable, Sendable {
        /// What the Pocket server knows it by, and what the config stores.
        public let name: String
        public let language: Language

        /// "peter_yearsley" → "Peter Yearsley".
        public var label: String { name.replacingOccurrences(of: "_", with: " ").capitalized }
    }

    /// The default first, so the first agent gets it; the rest alphabetically.
    public static let english: [Voice] = [
        "fantine", "alba", "anna", "azelma", "bill_boerst", "caro_davy", "charles", "eponine", "eve", "george",
        "jane", "javert", "marius", "mary", "michael", "paul", "peter_yearsley", "stuart_bell", "vera",
    ].map { Voice(name: $0, language: .english) }

    /// Kyutai's French model has every one of these voices; those left out sounded wrong or were transcribed wrongly.
    public static let french: [Voice] = ["estelle", "eve", "charles"].map { Voice(name: $0, language: .french) }

    public static func voices(for language: Language) -> [Voice] {
        switch language {
        case .english: english
        case .french: french
        }
    }

    public static func names(for language: Language = .english) -> [String] {
        voices(for: language).map(\.name)
    }

    public static func defaultName(for language: Language = .english) -> String {
        switch language {
        case .english: "fantine"
        case .french: "estelle"
        }
    }

    /// The voice to speak with for a configured name; one that isn't in the catalog (Kokoro's `af_heart` in an older
    /// config) gets the language's default.
    public static func resolve(_ configured: String, language: Language = .english) -> String {
        voices(for: language).contains { $0.name == configured } ? configured : defaultName(for: language)
    }

    /// How a configured name reads in Settings.
    public static func label(for configured: String, language: Language = .english) -> String {
        Voice(name: resolve(configured, language: language), language: language).label
    }
}
