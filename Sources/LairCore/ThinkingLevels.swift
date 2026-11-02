/// Where "think harder" and "think less" land among the levels an agent offers.
public enum ThinkingLevels {
    public static func step(_ by: Int, from current: String?, in levels: [String]) -> String? {
        guard !levels.isEmpty else { return nil }
        let index = current.flatMap { levels.firstIndex(of: $0) } ?? levels.firstIndex(of: "medium") ?? levels.count / 2
        return levels[min(max(index + by, 0), levels.count - 1)]
    }
}
