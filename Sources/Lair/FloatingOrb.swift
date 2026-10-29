import AppKit
import LairCore
import SwiftUI

/// During a call, the focused agent's orb floats above every window: click to talk, click again to send,
/// drag to move it.
@MainActor final class FloatingOrb {
    private let room: Room
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 112, height: 112),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var pointer: Timer?
    /// Clicks farther than this from the center go to the window below: the glow is see-through.
    private static let reach: CGFloat = 28

    init(room: Room) {
        self.room = room
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let content = NSView(frame: panel.contentLayoutRect)
        let orb = NSHostingView(rootView: FloatingOrbView(room: room))
        // The press view goes on top so the orb never swallows a click.
        let press = OrbPressView(room: room)
        for view in [orb, press] {
            view.frame = content.bounds
            view.autoresizingMask = [.width, .height]
            content.addSubview(view)
        }
        panel.contentView = content
        panel.setFrameAutosaveName("LairFloatingOrb")
        if !panel.setFrameUsingName("LairFloatingOrb"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 140, y: screen.minY + 40))
        }
        follow()
    }

    private func follow() {
        withObservationTracking {
            if room.calls.contains(where: \.inCall) { show() } else { hide() }
        } onChange: {
            Task { @MainActor in self.follow() }
        }
    }

    private func show() {
        panel.orderFrontRegardless()
        guard pointer == nil else { return }
        // Windows can't be shaped for clicks, so the panel ignores the mouse unless it's over the orb itself.
        pointer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPointer() }
        }
    }

    private func hide() {
        panel.orderOut(nil)
        pointer?.invalidate()
        pointer = nil
    }

    private func followPointer() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = NSEvent.mouseLocation, frame = panel.frame
        panel.ignoresMouseEvents = hypot(mouse.x - frame.midX, mouse.y - frame.midY) > Self.reach
    }
}

private struct FloatingOrbView: View {
    let room: Room

    var body: some View {
        if let call = room.focused {
            Orb(color: Color(hex: call.agent.color), state: call.state, meter: room.meter(for: call))
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private final class OrbPressView: NSView {
    private let room: Room
    private var pressedAt: NSPoint?

    init(room: Room) {
        self.room = room
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { pressedAt = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        // A hand that shakes a little while clicking is still a click.
        guard let start = pressedAt, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3
        else { return }
        pressedAt = nil
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressedAt != nil else { return }
        pressedAt = nil
        room.toggleTalk()
    }
}
