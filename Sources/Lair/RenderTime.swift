import SwiftUI

extension EnvironmentValues {
    /// Set when the UI is rendered offscreen (snapshots, the demo video): animations follow this clock,
    /// in seconds, instead of the wall clock, and scrolling views are drawn flat.
    @Entry var renderTime: Double? = nil
}
