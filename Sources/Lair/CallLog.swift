import Foundation
import LairCore

/// Everything that happened in a call, in order, for Mission Control: more than the panel's transcript.
struct LogEntry: Identifiable {
    enum Kind {
        case you(String)
        case agent(String)
        case thinking(String)
        case tool(name: String, input: String, output: String?, failed: Bool)
        case note(String)
        case problem(String)
        case approval(String)
        case usage(inputTokens: Int, outputTokens: Int, cost: Double?)
        /// One turn's timings, in milliseconds from the moment you let go of the key.
        case timing(heard: Int?, firstWord: Int?, firstSound: Int?, total: Int)
    }

    let id = UUID()
    let time = Date()
    /// The agent's own id for a tool call, so its result lands on the same card.
    var toolID: String?
    var kind: Kind
}

extension Call {
    func log(_ kind: LogEntry.Kind, toolID: String? = nil) {
        entries.append(LogEntry(toolID: toolID, kind: kind))
    }

    /// Streamed pieces join the entry before them when it's the same kind, so a reply reads as one block.
    func logText(_ text: String) {
        if case .agent(let previous) = entries.last?.kind {
            entries[entries.count - 1].kind = .agent(previous + text)
        } else {
            log(.agent(text))
        }
    }

    /// Named apart from `log(_:)`: both enums have a `usage` case, and the same name made this call itself.
    func record(_ activity: Activity) {
        switch activity {
        case .thinking(let text):
            if case .thinking(let previous) = entries.last?.kind {
                entries[entries.count - 1].kind = .thinking(previous + text)
            } else {
                log(.thinking(text))
            }
        case .toolStarted(let id, let name, let input):
            log(.tool(name: name, input: input, output: nil, failed: false), toolID: id)
        case .toolFinished(let id, let output, let failed):
            guard let index = entries.lastIndex(where: { $0.toolID == id }),
                  case .tool(let name, let input, _, _) = entries[index].kind
            else { return log(.tool(name: "tool", input: "", output: output, failed: failed), toolID: id) }
            entries[index].kind = .tool(name: name, input: input, output: output, failed: failed)
        case .helper(let text):
            log(.note(text))
        case .usage(let input, let output, let cost):
            log(.usage(inputTokens: input, outputTokens: output, cost: cost))
        }
    }
}
