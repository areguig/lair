import Foundation
@testable import LairCore
import Testing

/// Answers every request from `reply`, and keeps the last request seen.
final class CheckStub: URLProtocol {
    enum Reply { case http(Int, String, [String: String]), fail(URLError.Code) }
    nonisolated(unsafe) static var reply = Reply.http(200, "", [:])
    nonisolated(unsafe) static var seen: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen = request
        switch Self.reply {
        case .fail(let code): client?.urlProtocol(self, didFailWithError: URLError(code))
        case .http(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            if (300..<400).contains(status), let target = headers["Location"].flatMap(URL.init(string:)) {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ConnectionCheckTests {
    private let base = URL(string: "http://hermes.test:8642")!
    private let credentials = HermesSession.Credentials(apiKey: "k", headers: ["X-Proxy-Token": "t"])

    private func check(_ reply: CheckStub.Reply, base: URL? = nil) async -> ConnectionCheck {
        CheckStub.reply = reply
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CheckStub.self]
        return await HermesSession.check(baseURL: base ?? self.base, credentials: credentials,
                                         session: URLSession(configuration: configuration))
    }

    @Test func listsTheModelsWithTheCallsAuthAndHeaders() async throws {
        let result = await check(.http(200, #"{"data":[{"id":"hermes-agent"}]}"#, [:]))
        #expect(result == .connected(models: ["hermes-agent"]))
        #expect(result.message == "Connected · hermes-agent")
        let request = try #require(CheckStub.seen)
        #expect(request.url?.absoluteString == "http://hermes.test:8642/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(request.value(forHTTPHeaderField: "X-Proxy-Token") == "t")
        #expect(request.timeoutInterval == 10)
    }

    @Test func countsSeveralModels() async {
        let result = await check(.http(200, #"{"data":[{"id":"a"},{"id":"b"}]}"#, [:]))
        #expect(result.message == "Connected · 2 models")
    }

    @Test func connectsWhenThereAreNoModelsToName() async {
        let result = await check(.http(200, #"{"data":[]}"#, [:]))
        #expect(result.isConnected)
        #expect(result.message == "Connected")
    }

    @Test(arguments: [401, 403]) func aRefusedKeyIsNamed(code: Int) async {
        #expect(await check(.http(code, "", [:])) == .refused(code))
    }

    @Test func aRedirectToALoginPageIsAProxy() async {
        let result = await check(.http(302, "", ["Location": "http://hermes.test/login"]))
        #expect(result == .proxy)
    }

    @Test func aPageInsteadOfJSONIsAProxy() async {
        #expect(await check(.http(200, "<html>Sign in</html>", [:])) == .proxy)
    }

    @Test func otherStatusesShowTheirCode() async {
        let result = await check(.http(502, "", [:]))
        #expect(result == .status(502))
        #expect(result.message == "Hermes answered HTTP 502.")
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .cannotFindHost])
    func anUnreachableAddressIsSaid(code: URLError.Code) async {
        #expect(await check(.fail(code)) == .unreachable)
    }

    @Test func anAddressThatIsNotWebIsNoAddress() async {
        #expect(await check(.http(200, "", [:]), base: URL(string: "ftp://hermes.test")!) == .noAddress)
        #expect(await check(.http(200, "", [:]), base: URL(string: "hermes")!) == .noAddress)
    }
}
