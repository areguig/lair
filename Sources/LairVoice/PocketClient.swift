import Foundation

/// Talks HTTP to a running `pocket-tts serve`.
struct PocketClient: Sendable {
    enum Failure: Error, LocalizedError {
        case server(status: Int, detail: String)

        var errorDescription: String? {
            switch self {
            case .server(let status, let detail): "The voice server answered \(status): \(detail)"
            }
        }
    }

    var session: URLSession = .shared

    func isHealthy(at base: URL) async -> Bool {
        guard let (_, response) = try? await session.data(from: base.appending(path: "health")) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// 24 kHz mono samples of `text` said in the built-in voice `voice`.
    func speech(for text: String, voice: String, at base: URL) async throws -> [Float] {
        var request = URLRequest(url: base.appending(path: "tts"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.form(["text": text, "voice_url": voice]).utf8)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure.server(status: status, detail: String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try WavReader.samples(from: data)
    }

    /// Percent-encodes everything but unreserved characters: `+` and `&` in a sentence must not read as form syntax.
    static func form(_ fields: KeyValuePairs<String, String>) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }
}
