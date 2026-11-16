import AppKit
import LairCore

/// Going on with a call in the agent's own CLI, and back to voice when that CLI quits.
extension Room {
    /// Agents whose CLI picks up the sessions Lair starts.
    func canHandOff(_ call: Call) -> Bool {
        !call.guest && call.agent.kind == .acp && KeyboardHandoff.command(preset: call.agent.preset, sessionID: "") != nil
    }

    /// Terminal always is; herdr also needs its command on your PATH, since Lair drives it from there.
    func isInstalled(_ terminal: KeyboardHandoff.Terminal) -> Bool {
        guard terminal != .terminal else { return true }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) != nil else { return false }
        return terminal != .herdr || isInstalled(program: "herdr-app") != false
    }

    func atKeyboardHint(_ call: Call) -> String {
        "\(call.agent.name) is at your keyboard · quit its CLI to bring it back"
    }

    /// Hangs up between turns and opens the agent's CLI on the same session; Lair stays quiet for it meanwhile.
    func handOff(_ call: Call) {
        guard call.state == .ready, let session = call.session else {
            return show(hint: "\(call.agent.name) can go to the keyboard once it's done with this turn.")
        }
        Task {
            guard let id = await session.resumableID,
                  let command = KeyboardHandoff.command(preset: call.agent.preset, sessionID: id) else {
                return report(in: call, .init(role: .problem, text: "\(call.agent.name) can't go on at the keyboard."))
            }
            var terminal = keyboardTerminal
            if !isInstalled(terminal) {
                show(hint: "\(terminal.name) isn't installed, so it opens in Terminal.")
                terminal = .terminal
            }
            let folder = (call.agent.directoryURL ?? FileManager.default.homeDirectoryForCurrentUser).path
            let back = KeyboardHandoff.Back(agent: call.id, sessionID: id)
            let script = KeyboardHandoff.script(command: command, folder: folder, path: environment?["PATH"], back: back)
            // The CLI must not open the session while this call still holds it.
            hangUp(call)
            call.atKeyboard = id
            do {
                let file = try Self.write(script, for: call.id)
                let launch = terminal == .herdr
                    ? KeyboardHandoff.herdrLaunch(file, folder: folder,
                                                  list: Data(try await Self.run(KeyboardHandoff.herdrList, environment: environment).utf8))
                    : KeyboardHandoff.windowLaunch(file, in: terminal)
                _ = try await Self.run(launch, environment: environment)
                Self.log.notice("\(call.id, privacy: .public): went on at the keyboard in \(terminal.rawValue, privacy: .public)")
            } catch {
                reopen(call, id)
                report(in: call, .init(role: .problem, text: "Couldn't open the terminal: \(error.localizedDescription)"))
            }
        }
    }

    /// `lair://back`: the CLI quit, so the call it had is picked up again.
    func takeBack(_ back: KeyboardHandoff.Back) {
        guard let call = calls.first(where: { $0.id == back.agent }), !call.inCall else { return }
        // A newer hand-off of this agent is still at the keyboard.
        guard call.atKeyboard == nil || call.atKeyboard == back.sessionID else { return }
        guard readiness == .ready else { return pendingBack = back }
        reopen(call, back.sessionID)
    }

    /// The call button while the agent is at the keyboard: only once its CLI is gone, or both would write the session.
    func takeBackByHand(_ call: Call) {
        guard let id = call.atKeyboard else { return }
        Task {
            if await Self.isRunning(sessionID: id) { return show(hint: "Quit \(call.agent.name) in the terminal first.") }
            if call.atKeyboard == id { reopen(call, id) }
        }
    }

    private func reopen(_ call: Call, _ id: String) {
        call.atKeyboard = nil
        summon(call, reopening: id)
        if call.inCall { call.lines.append(.init(role: .info, text: "Back from the keyboard")) }
    }

    /// The script lives with Lair's other files, one per agent, replaced at each hand-off.
    private static func write(_ script: String, for agentID: String) throws -> URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Lair/Keyboard")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(agentID).command")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    /// Runs `command` and returns what it printed; failing, it throws what it said.
    private static func run(_ command: [String], environment: [String: String]?) async throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: command[0])
        process.arguments = Array(command.dropFirst())
        if let environment { process.environment = environment }
        let result = try await ProcessRun.run(process, includingErrors: true)
        guard result.status == 0 else {
            throw AgentFailure(message: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output
    }

    /// Whether a CLI still runs with this session on its command line.
    private static func isRunning(sessionID: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        process.arguments = ["-f", "--", sessionID]
        return (try? await ProcessRun.run(process))?.status == 0
    }
}
