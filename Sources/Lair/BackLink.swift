import AppKit
import LairCore

/// Receives `lair://back` when an agent's CLI quits, and gives its call back to Lair's voice.
@MainActor final class BackLink: NSObject {
    private let room: Room

    init(room: Room) {
        self.room = room
        super.init()
        // AppKit sets its own handler while launching, so this one goes in after it and before the launch link arrives.
        NotificationCenter.default.addObserver(self, selector: #selector(listen), name: NSApplication.willFinishLaunchingNotification,
                                               object: nil)
    }

    @objc private func listen() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(open(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func open(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text), let back = KeyboardHandoff.Back(url: url) else { return }
        room.takeBack(back)
    }
}
