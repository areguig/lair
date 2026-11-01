import Foundation
import LairCore
import Testing

@Suite struct VisitorsTests {
    private let agents = [
        AgentConfig(id: "checkout", name: "Checkout", preset: .claude, voice: "af_heart", color: "#D97757",
                    directory: "~/dev/checkout-api"),
        AgentConfig(id: "web", name: "Web", preset: .omp, voice: "bf_emma", color: "#7B5CFF", directory: "~/dev/landing-page"),
        AgentConfig(id: "home", name: "Home", preset: .claude, voice: "am_adam", color: "#3FB68B", directory: "~"),
    ]
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @Test func aSessionIsTheAgentWithItsToolAndFolder() {
        let folder = home.appending(path: "dev/checkout-api")
        #expect(Visitors.agent(client: "claude-code", folder: folder, in: agents)?.id == "checkout")
        #expect(Visitors.agent(client: "omp-coding-agent", folder: home.appending(path: "dev/landing-page"), in: agents)?.id == "web")
    }

    @Test func anotherToolOrFolderIsNoOne() {
        #expect(Visitors.agent(client: "omp-coding-agent", folder: home.appending(path: "dev/checkout-api"), in: agents) == nil)
        #expect(Visitors.agent(client: "claude-code", folder: home.appending(path: "dev/elsewhere"), in: agents) == nil)
        #expect(Visitors.agent(client: "zed", folder: home.appending(path: "dev/checkout-api"), in: agents) == nil)
        #expect(Visitors.agent(client: "claude-code", folder: nil, in: agents) == nil)
    }

    /// An agent in your home folder would otherwise claim every session on the Mac.
    @Test func aParentFolderDoesntClaimTheSessionsBelowIt() {
        #expect(Visitors.agent(client: "claude-code", folder: home.appending(path: "dev/lair"), in: agents) == nil)
        #expect(Visitors.agent(client: "claude-code", folder: home, in: agents)?.id == "home")
    }

    @Test func symlinkedFoldersAreTheSameFolder() throws {
        let real = URL(fileURLWithPath: "/private/tmp/lair-visitors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let agent = AgentConfig(id: "tmp", name: "Tmp", preset: .omp, voice: "af_heart", color: "#000000", directory: real.path)
        let viaLink = URL(fileURLWithPath: "/tmp/" + real.lastPathComponent)
        #expect(Visitors.agent(client: "omp-coding-agent", folder: viaLink, in: [agent])?.id == "tmp")
    }

    @Test func copiesAreNumberedLikeFinderCopies() {
        #expect(Visitors.name("Checkout", taken: []) == "Checkout")
        #expect(Visitors.name("Checkout", taken: ["Checkout"]) == "Checkout (1)")
        #expect(Visitors.name("Checkout", taken: ["Checkout", "Checkout (1)"]) == "Checkout (2)")
    }

    @Test func aNewAgentIsNamedAfterItsFolder() {
        #expect(Visitors.agentName(for: URL(fileURLWithPath: "/Users/me/dev/checkout-api")) == "Checkout api")
        #expect(Visitors.agentName(for: URL(fileURLWithPath: "/Users/me/dev/lair")) == "Lair")
    }

    @Test func foldersInHomeAreWrittenWithATilde() {
        #expect(Visitors.configPath(home.appending(path: "dev/lair")) == "~/dev/lair")
        #expect(Visitors.configPath(home) == "~")
        #expect(Visitors.configPath(URL(fileURLWithPath: "/opt/work")) == "/opt/work")
    }
}
