import Foundation
@testable import LairCore
import Testing

struct OmpSessionTests {
    /// omp answers `get_available_models` only once its model discovery is done, which can take seconds.
    @Test func passesOnModelsListedLate() async throws {
        let bin = FileManager.default.temporaryDirectory.appending(path: "lair-omp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bin) }
        let omp = bin.appending(path: "omp")
        try """
            #!/bin/sh
            sleep 1
            echo '{"type":"response","command":"get_available_models","success":true,\
            "data":{"models":[{"provider":"github-copilot","id":"claude-haiku-5.5"}]}}'
            cat > /dev/null
            """.write(to: omp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: omp.path)

        let session = try OmpSession(environment: ["PATH": "\(bin.path):/usr/bin:/bin"])
        defer { session.stop() }
        var models = session.models.makeAsyncIterator()
        #expect(await models.next() == ["claude-haiku-5.5"])
    }
}
