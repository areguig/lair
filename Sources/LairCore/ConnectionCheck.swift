import Foundation

/// What asking a Hermes address for its models showed, in words Settings can put next to the button.
public enum ConnectionCheck: Equatable, Sendable {
    case connected(models: [String])
    /// The address is empty, or not a web address.
    case noAddress
    case noKey
    /// Offline, an unknown host, a refused connection or no answer in time.
    case unreachable
    /// The key (or a header's token) was turned down: HTTP 401 or 403.
    case refused(Int)
    /// A redirect or a page answered where Hermes's JSON should be, as a login page in front of it does.
    case proxy
    case status(Int)

    public var isConnected: Bool {
        if case .connected = self { true } else { false }
    }

    public var message: String {
        switch self {
        case .connected(let models):
            switch models.count {
            case 0: "Connected"
            case 1: "Connected · \(models[0])"
            default: "Connected · \(models.count) models"
            }
        case .noAddress: "Add the address first, like http://hermes.local:8642."
        case .noKey: "Add the API key first."
        case .unreachable: "Can't reach the address. Check it, your network and that Hermes is running."
        case .refused(let code): "The key was refused (HTTP \(code)). Check the API key and any extra headers."
        case .proxy: "Something in front of Hermes answered, such as a login page. Check the extra headers."
        case .status(let code): "Hermes answered HTTP \(code)."
        }
    }
}

extension HermesSession {
    /// How long a check waits before calling the address unreachable.
    static let checkTimeout: TimeInterval = 10

    /// Asks the address for its models with the auth and headers a call would use, so a wrong address, key or header shows
    /// before the first call does.
    public static func check(baseURL: URL, credentials: Credentials, session: URLSession = .shared) async -> ConnectionCheck {
        guard ["http", "https"].contains(baseURL.scheme?.lowercased()), baseURL.host() != nil else { return .noAddress }
        var request = URLRequest(url: baseURL.appending(path: "v1/models"), timeoutInterval: checkTimeout)
        authorize(&request, with: credentials)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoRedirects.shared)
        } catch {
            return .unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            guard let models = models(in: data) else { return .proxy }
            return .connected(models: models)
        case 401, 403: return .refused(status)
        case 300..<400: return .proxy
        default: return .status(status)
        }
    }

    /// The model ids of an OpenAI-style list, or nil when the body isn't one.
    static func models(in data: Data) -> [String]? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let models = list["data"] as? [[String: Any]]
        else { return nil }
        return models.compactMap { $0["id"] as? String }
    }
}
