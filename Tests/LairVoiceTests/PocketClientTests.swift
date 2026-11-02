import Foundation
@testable import LairVoice
import Testing

/// Answers every request with `Stub.respond`, so the client talks to no server.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, Data) = { _ in (200, Data()) }
    nonisolated(unsafe) static var seen: [URLRequest] = []
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.append(request)
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            var body = Data()
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            Self.body = body
        } else {
            Self.body = request.httpBody ?? Data()
        }
        let (status, data) = Self.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Serialized: the stub's state is shared.
@Suite(.serialized) struct PocketClientTests {
    private let base = URL(string: "http://127.0.0.1:9")!

    private func client() -> PocketClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.seen = []
        return PocketClient(session: URLSession(configuration: configuration))
    }

    @Test func postsTheTextAndVoiceAsAForm() async throws {
        let client = client()
        StubProtocol.respond = { _ in (200, WavReaderTests.wav([16384, -16384])) }
        let samples = try await client.speech(for: "Tom & Jerry + you", voice: "fantine", at: base)
        #expect(samples == [0.5, -0.5])
        let request = try #require(StubProtocol.seen.first)
        #expect(request.httpMethod == "POST" && request.url?.path == "/tts")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(String(decoding: StubProtocol.body, as: UTF8.self) == "text=Tom%20%26%20Jerry%20%2B%20you&voice_url=fantine")
    }

    @Test func aServerErrorSaysWhatItAnswered() async {
        let client = client()
        StubProtocol.respond = { _ in (400, Data(#"{"detail":"Text cannot be empty"}"#.utf8)) }
        await #expect(throws: PocketClient.Failure.self) { try await client.speech(for: " ", voice: "fantine", at: base) }
        do { _ = try await client.speech(for: " ", voice: "fantine", at: base) } catch {
            #expect(error.localizedDescription.contains("400") && error.localizedDescription.contains("Text cannot be empty"))
        }
    }

    @Test func healthIsA200OnHealth() async {
        let client = client()
        StubProtocol.respond = { _ in (200, Data(#"{"status":"healthy"}"#.utf8)) }
        #expect(await client.isHealthy(at: base))
        #expect(StubProtocol.seen.first?.url?.path == "/health")
        StubProtocol.respond = { _ in (503, Data()) }
        #expect(await !client.isHealthy(at: base))
    }

    @Test func formEncodingLeavesNoFormSyntaxInValues() {
        #expect(PocketClient.form(["a": "x=1&y", "b": "é"]) == "a=x%3D1%26y&b=%C3%A9")
    }
}
