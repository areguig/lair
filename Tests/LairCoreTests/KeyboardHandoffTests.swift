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

    @Test func theBackLinkSaysWhoComesBack() throws {
        let back = KeyboardHandoff.Back(agent: "my agent", sessionID: "777c-55f4")
        #expect(back.url.absoluteString == "lair://back?agent=my%20agent&session=777c-55f4")
        #expect(KeyboardHandoff.Back(url: back.url) == back)
        #expect(KeyboardHandoff.Back(url: try #require(URL(string: "lair://back?agent=a"))) == nil)
        #expect(KeyboardHandoff.Back(url: try #require(URL(string: "https://back?agent=a&session=s"))) == nil)
    }

    @Test func theScriptRunsTheCLIInTheFolderAndGivesTheCallBackWhenItEnds() {
        let script = KeyboardHandoff.script(command: ["claude", "--resume", "s1"], folder: "/work/it's here",
                                            path: "/opt/bin:/usr/bin", back: .init(agent: "claude", sessionID: "s1"))
        #expect(script == """
            #!/bin/sh
            # Lair: quitting the CLI gives the conversation back to Lair's voice.
            back='lair://back?agent=claude&session=s1'
            trap '/usr/bin/open -g "$back"; [ -z "$HC_TERMINAL_ID" ] || hc kill "$HC_TERMINAL_ID" >/dev/null 2>&1' EXIT
            trap 'exit' HUP INT TERM
            export PATH='/opt/bin:/usr/bin'
            cd '/work/it'\\''s here' || exit 1
            'claude' '--resume' 's1'

            """)
    }

    @Test func theScriptReallyGivesTheCallBack() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "handoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // `open` stands in for the system's: it notes the link it was given.
        let fake = folder.appending(path: "open")
        try "#!/bin/sh\necho \"$2\" > \"\(folder.path)/opened\"\n".write(to: fake, atomically: true, encoding: .utf8)
        var script = KeyboardHandoff.script(command: ["true"], folder: folder.path, path: nil, back: .init(agent: "a", sessionID: "s"))
        script = script.replacingOccurrences(of: "/usr/bin/open", with: "/bin/sh \(fake.path)")
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]
        // Run from a herdr pane, the script would close that pane on exit.
        process.environment = ProcessInfo.processInfo.environment.filter { $0.key != "HC_TERMINAL_ID" }
        _ = try await ProcessRun.run(process)
        let opened = try String(contentsOf: folder.appending(path: "opened"), encoding: .utf8)
        #expect(opened == "lair://back?agent=a&session=s\n")
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
