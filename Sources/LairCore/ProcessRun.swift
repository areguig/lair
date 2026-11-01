import Foundation

/// Runs a short command to its end and returns what it printed.
///
/// The wait happens on a system thread, never on one of Swift's task threads, and the output is read while the
/// command runs, so one that prints more than a pipe holds can't stall waiting for a reader.
public enum ProcessRun {
    public struct Result: Sendable {
        public let output: String
        public let status: Int32
    }

    /// `process` comes with its executable, arguments and environment set; its standard streams are set here.
    public static func run(_ process: Process, includingErrors: Bool = false) async throws -> Result {
        let output = Pipe()
        process.standardOutput = output
        process.standardError = includingErrors ? output : FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                } catch {
                    return continuation.resume(throwing: error)
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: Result(output: String(decoding: data, as: UTF8.self),
                                                      status: process.terminationStatus))
            }
        }
    }
}
