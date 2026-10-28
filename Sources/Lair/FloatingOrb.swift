import AppKit
import LairCore
import SwiftUI

/// During a call, the focused agent's orb floats above every window: click to talk, hold to talk while held,
/// double-click to open Lair, drag to move it.
@MainActor final class FloatingOrb {
    private let room: Room
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 112, height: 112),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)

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

    /// SwiftUI can't open a menu-bar extra from code; clicking its status-bar button does, and closes it when open.
    static func togglePanel() {
        func button(in view: NSView?) -> NSStatusBarButton? {
            guard let view else { return nil }
            return view as? NSStatusBarButton ?? view.subviews.lazy.compactMap(button(in:)).first
        }
        NSApp.windows.lazy.compactMap { button(in: $0.contentView) }.first?.performClick(nil)
    }

    private func follow() {
        withObservationTracking {
            if room.calls.contains(where: \.inCall) { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        } onChange: {
            Task { @MainActor in self.follow() }
        }
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
    private var press = OrbPress()
    private var wait: Task<Void, Never>?
    private var lastEffect: OrbPress.Effect?

    init(room: Room) {
        self.room = room
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { handle(.down(clicks: event.clickCount)) }

    override func mouseDragged(with event: NSEvent) {
        handle(.moved)
        guard case .drag? = lastEffect else { return }
        // The window's own drag loop takes the mouse-up.
        window?.performDrag(with: event)
        handle(.up)
    }

    override func mouseUp(with event: NSEvent) { handle(.up) }

    private func handle(_ input: OrbPress.Input) {
        let effect = press.handle(input)
        lastEffect = effect
        guard let effect else { return }
        wait?.cancel()
        switch effect {
        case .wait:
            wait = Task { [weak self] in
                try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
                guard !Task.isCancelled else { return }
                self?.handle(.timeout)
            }
        case .startHold: room.pressTalk()
        case .endHold: room.releaseTalk()
        case .toggleTalk: room.toggleTalk()
        case .openPanel: FloatingOrb.togglePanel()
        case .drag: break
        }
    }
}
