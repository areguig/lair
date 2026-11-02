import Foundation

/// How long a silent answer stays on the island after its turn ends, so there is time to read it.
public enum ReadingTime {
    public static let base = Duration.seconds(3)
    public static let perCharacter = Duration.milliseconds(50)
    public static let longest = Duration.seconds(15)

    public static func duration(for text: String) -> Duration {
        min(base + perCharacter * text.count, longest)
    }
}
