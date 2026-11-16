import Foundation
@testable import LairCore
import Testing

struct KeyboardHandoffTests {
    @Test func picksTheSessionUpInTheCLIsThatShareTheirSessions() {
        #expect(KeyboardHandoff.command(preset: "claude", sessionID: "s1") == ["claude", "--resume", "s1"])
        #expect(KeyboardHandoff.command(preset: "codex", sessionID: "s1") == ["codex", "resume", "--no-daemon", "s1"])
        #expect(KeyboardHandoff.command(preset: "copilot", sessionID: "s1") == nil)
        #expect(KeyboardHandoff.command(preset: nil, sessionID: "s1") == nil)
    }

    @Test func theScriptRunsTheCLIInTheFolderWithYourPath() {
        let script = KeyboardHandoff.script(command: ["claude", "--resume", "s1"], folder: "/work/it's here", path: "/opt/bin:/usr/bin")
        #expect(script == """
            #!/bin/sh
            # Lair: once this CLI quits, Lair picks the conversation up again by voice.
            trap '[ -z "$HC_TERMINAL_ID" ] || hc kill "$HC_TERMINAL_ID" >/dev/null 2>&1' EXIT
            trap 'exit' HUP INT TERM
            export PATH='/opt/bin:/usr/bin'
            cd '/work/it'\\''s here' || exit 1
            'claude' '--resume' 's1'

            """)
    }

    @Test func theScriptRunsTheCommandInTheFolder() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "handoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", KeyboardHandoff.script(command: ["/bin/pwd"], folder: folder.path, path: nil)]
        // Run from a herdr pane, the script would close that pane on exit.
        process.environment = ProcessInfo.processInfo.environment.filter { $0.key != "HC_TERMINAL_ID" }
        let output = try await ProcessRun.run(process).output
        #expect(output == folder.resolvingSymlinksInPath().path + "\n")
    }

    @Test func opensANewWindowInTheChosenTerminal() {
        let file = URL(filePath: "/tmp/claude.command")
        #expect(KeyboardHandoff.windowLaunch(file, in: .terminal) == ["/usr/bin/open", "-a", "Terminal", "/tmp/claude.command"])
        #expect(KeyboardHandoff.windowLaunch(file, in: .iterm) == ["/usr/bin/open", "-a", "iTerm", "/tmp/claude.command"])
        #expect(KeyboardHandoff.windowLaunch(file, in: .ghostty)
            == ["/usr/bin/open", "-na", "Ghostty", "--args", "-e", "/bin/sh", "/tmp/claude.command"])
    }

    @Test func theFirstAgentAtTheKeyboardMakesTheLairSpaceInHerdr() {
        let list = Data(#"{"spaces":[{"name":"PERSO","tabs":[{"terminals":[{"terminal":"t1","pane":"p1"}]}]}]}"#.utf8)
        #expect(KeyboardHandoff.herdrLaunch(URL(filePath: "/tmp/claude.command"), folder: "/work", list: list)
            == ["/usr/bin/env", "herdr-app", "do", "space.new",
                #"{"argv":["/bin/sh","/tmp/claude.command"],"folder":"/work","name":"Lair","tab":"Agents"}"#])
    }

    @Test func theNextOnesJoinItsTab() {
        let list = Data(#"{"spaces":[{"name":"Lair","tabs":[{"terminals":[{"pane":"p1"},{"pane":"p2"}]},{"terminals":[{"pane":"p9"}]}]}]}"#.utf8)
        #expect(KeyboardHandoff.herdrLaunch(URL(filePath: "/tmp/codex.command"), folder: "/work", list: list)
            == ["/usr/bin/env", "herdr-app", "do", "pane.split",
                #"{"argv":["/bin/sh","/tmp/codex.command"],"direction":"right","pane":"p2"}"#])
    }
}
