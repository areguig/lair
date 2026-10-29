import Foundation
import LairCore
import LairMCP
import Observation
import os

/// Runs the guest server while the config turns it on, on the port it names.
@Observable @MainActor final class GuestLink {
    enum Status: Equatable {
        case off, on(URL), failed(String)
    }

    /// Settable so snapshots can stage it.
    var status = Status.off
    @ObservationIgnored private let room: Room
    @ObservationIgnored private var server: Task<Void, Never>?
    @ObservationIgnored private var port: Int?
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lair", category: "guests")

    init(room: Room) {
        self.room = room
    }

    func apply(_ settings: GuestSettings?) {
        guard settings?.port != port else { return }
        server?.cancel()
        port = settings?.port
        guard let settings else { return status = .off }
        let token: String
        do {
            token = try GuestConnection.token()
        } catch {
            return status = .failed("Couldn't make Lair's token: \(error.localizedDescription)")
        }
        status = .on(settings.url)
        let host = RoomGuests(room: room)
        server = Task {
            do {
                try await GuestServer(host: host, token: token).run(port: settings.port)
            } catch where !Task.isCancelled {
                Self.log.error("guest server: \(error, privacy: .public)")
                status = .failed("Port \(settings.port) is taken by another app. Pick another in the config file.")
            } catch {}
        }
    }
}
