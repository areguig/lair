import Foundation
import LairACP
import LairCore

enum SetupError: Error {
    case missingAddress, missingKey, missingCommand, missingProgram(AgentPreset), guest

    func message(for name: String) -> String {
        switch self {
        case .missingAddress: "\(name) needs an address. Add it in Settings › Agents."
        case .missingKey: "\(name) needs an API key. Add it in Settings › Agents."
        case .missingCommand: "\(name) needs a command to start it. Add it in Settings › Agents."
        case .missingProgram(let preset): "\(name) needs \(preset.needs): \(preset.installURL.absoluteString)"
        case .guest: "\(name) runs on its own; it talks to you when it needs you."
        }
    }
}

/// Starts the session an agent's call runs on, with the PATH of the login shell.
struct SessionMaker {
    let environment: [String: String]?

    /// How long an agent's own turn waits for more before it's over: ACP v1 marks no end for those turns.
    private static let ownTurnQuiet = Duration.seconds(2)

    func session(for agent: AgentConfig, thinking: String?, prompt: String) throws -> any AgentSession {
        switch agent.kind {
        case .acp:
            guard let command = agent.launchCommand else { throw SetupError.missingCommand }
            if let preset = AgentPreset.withID(agent.preset), !preset.isInstalled(path: environment?["PATH"]) {
                throw SetupError.missingProgram(preset)
            }
            let channel = try ProcessChannel(command: command, directory: agent.directoryURL,
                                             environment: agent.launchEnvironment(over: environment),
                                             errorLog: AgentLog.url(for: agent.id))
            let folder = agent.directoryURL ?? FileManager.default.homeDirectoryForCurrentUser
            return AcpSession(channel: channel, settings: .init(directory: folder.path, preamble: prompt,
                                                                ownTurnQuiet: Self.ownTurnQuiet, model: agent.model,
                                                                thinking: thinking, options: agent.options ?? [:]))
        case .hermes:
            guard let url = agent.url.flatMap(URL.init(string:)), url.host() != nil else { throw SetupError.missingAddress }
            guard let credentials = agent.hermesCredentials() else { throw SetupError.missingKey }
            return HermesSession(baseURL: url, credentials: credentials, model: agent.model)
        case .guest:
            throw SetupError.guest
        }
    }
}

extension AgentConfig {
    /// The key and extra headers a Hermes call sends, from the Keychain; nil without a key.
    func hermesCredentials() -> HermesSession.Credentials? {
        let secret = { Keychain.password(service: keychainService, account: $0) }
        guard let apiKey = secret("api-key") else { return nil }
        var headers: [String: String] = [:]
        for name in self.headers ?? [] { headers[name] = secret(AgentConfig.headerAccount(name)) }
        return .init(apiKey: apiKey, headers: headers)
    }

    /// Asks the Hermes address as saved whether a call would get through.
    func checkConnection() async -> ConnectionCheck {
        guard let url = url.flatMap(URL.init(string:)), url.host() != nil else { return .noAddress }
        guard let credentials = hermesCredentials() else { return .noKey }
        return await HermesSession.check(baseURL: url, credentials: credentials)
    }
}
