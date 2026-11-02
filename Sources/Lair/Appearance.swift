import SwiftUI

// MARK: Appearance

extension Color {
    /// The window's own background: what text sits on, and so what reads on top of a `.primary` fill.
    static let inverse = Color(nsColor: .windowBackgroundColor)
}

extension View {
    /// Animates a change, unless Reduce Motion is on.
    func motion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(Motion(animation: animation, value: value))
    }

    /// A control's surface: Liquid Glass on macOS 26, a soft fill before it and under Reduce Transparency.
    func controlSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil) -> some View {
        modifier(ControlSurface(shape: shape, tint: tint))
    }

    /// A border that grows stronger under Increase Contrast. `opacity` is its strength otherwise; 0 for none.
    func outlined<S: InsettableShape>(_ shape: S, _ color: Color = .primary, opacity: Double) -> some View {
        modifier(Outline(shape: shape, color: color, opacity: opacity))
    }
}

private struct Motion<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct ControlSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.renderTime) private var renderTime

    func body(content: Content) -> some View {
        // Glass doesn't render offscreen, so snapshots get the fallback.
        if #available(macOS 26, *), !reduceTransparency, renderTime == nil {
            // Glass isn't hit-testable: without the shape, a plain button only takes clicks on its symbol.
            content
                .contentShape(shape)
                .glassEffect(tint.map { .regular.tint($0).interactive() } ?? .regular.interactive(), in: shape)
        } else {
            content
                .background(tint ?? (reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.1)), in: shape)
                .outlined(shape, opacity: reduceTransparency ? 0.2 : 0)
        }
    }
}

private struct Outline<S: InsettableShape>: ViewModifier {
    let shape: S
    let color: Color
    let opacity: Double
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let increased = contrast == .increased
        content.overlay(shape.strokeBorder(color.opacity(increased ? max(opacity, 0.6) : opacity), lineWidth: increased ? 1.5 : 1))
    }
}
