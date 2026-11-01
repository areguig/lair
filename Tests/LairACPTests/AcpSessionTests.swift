import Foundation
@testable import LairACP
import LairCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct AcpSessionTests {
    private func session(_ agent: FakeAgent, preamble: String? = "You are heard by voice.",
                         quiet: Duration = .milliseconds(50)) -> AcpSession {
        AcpSession(channel: agent, settings: .init(directory: "/work", preamble: preamble, ownTurnQuiet: quiet))
    }

    @Test func startsWithInitializeThenANewSessionInTheFolder() async {
        let agent = FakeAgent()
        let session = session(agent)
        let (initialize, newSession) = await agent.handshake()
        #expect(initialize.method == "initialize")
        #expect(initialize.params["protocolVersion"] as? Int == 1)
        #expect(newSession.method == "session/new")
        #expect(newSession.params["cwd"] as? String == "/work")
        session.stop()
    }

    @Test func tellsTheModelAndThinkingLevelAndListsTheModels() async {
        let agent = FakeAgent()
        let session = session(agent)
        var details = session.details.makeAsyncIterator()
        var models = session.models.makeAsyncIterator()
        await agent.handshake()
        #expect(await models.next() == ["Sonnet", "Claude Opus"])
        #expect(await details.next() == "Sonnet · low thinking")
        #expect(session.thinkingLevels == ["low", "high"])
        session.stop()
    }

    @Test func yourTurnIsThePromptAndSaysThePreambleOnlyFirst() async throws {
        let agent = FakeAgent()
        let session = session(agent)
        await agent.handshake()

        let first = try session.ask("Hi")
        let prompt = await agent.next()
        #expect(prompt.method == "session/prompt")
        #expect((prompt.params["prompt"] as? [[String: Any]])?.compactMap { $0["text"] as? String } == ["You are heard by voice.", "Hi"])
        agent.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello"}}"#)
        agent.update(#"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"hmm"}}"#)
        agent.answer(prompt, #"{"stopReason":"end_turn","usage":{"inputTokens":3,"outputTokens":2,"cachedReadTokens":5}}"#)
        #expect(try await collect(first) == [.text("Hello"), .activity(.thinking("hmm")),
                                             .activity(.usage(inputTokens: 8, outputTokens: 2, cost: nil))])

        let second = try session.ask("Again")
        let next = await agent.next()
        #expect((next.params["prompt"] as? [[String: Any]])?.compactMap { $0["text"] as? String } == ["Again"])
        agent.answer(next, #"{"stopReason":"end_turn"}"#)
        #expect(try await collect(second).isEmpty)
        session.stop()
    }

    @Test func whatTheAgentSaysWithNoPromptIsATurnOfItsOwnThatEndsWhenQuiet() async throws {
        let agent = FakeAgent()
        let session = session(agent)
        await agent.handshake()
        var own = session.ownTurns.makeAsyncIterator()
        agent.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"The build passed."}}"#)
        let turn = try #require(await own.next())
        #expect(try await collect(turn) == [.text("The build passed.")])
        session.stop()
    }

    @Test func speakingEndsTheAgentsOwnTurn() async throws {
        let agent = FakeAgent()
        let session = session(agent, quiet: .seconds(30))
        await agent.handshake()
        var own = session.ownTurns.makeAsyncIterator()
        agent.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Done."}}"#)
        let turn = try #require(await own.next())
        let reply = try session.ask("Thanks")
        #expect(try await collect(turn) == [.text("Done.")])
        let prompt = await agent.next()
        agent.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Welcome."}}"#)
        agent.answer(prompt, #"{"stopReason":"end_turn"}"#)
        #expect(try await collect(reply) == [.text("Welcome.")])
        session.stop()
    }

    @Test func toolCallsBecomeActivity() async throws {
        let agent = FakeAgent()
        let session = session(agent)
        await agent.handshake()
        let reply = try session.ask("Run it")
        let prompt = await agent.next()
        agent.update(#"{"sessionUpdate":"tool_call","toolCallId":"t1","title":"$ make","status":"pending","rawInput":{"command":"make"}}"#)
        agent.update(#"{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"in_progress"}"#)
        agent.update(#"{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"completed","content":[{"type":"content","content":{"type":"text","text":"ok"}}]}"#)
        agent.answer(prompt, #"{"stopReason":"end_turn"}"#)
        #expect(try await collect(reply) == [
            .activity(.toolStarted(id: "t1", name: "$ make", input: #"{"command":"make"}"#)),
            .activity(.toolFinished(id: "t1", output: "ok", failed: false)),
        ])
        session.stop()
    }

    @Test func anApprovalIsAnsweredWithTheOptionOfTheChosenKind() async throws {
        let agent = FakeAgent()
        let session = session(agent)
        await agent.handshake()
        var replies = try session.ask("Delete it").makeAsyncIterator()
        _ = await agent.next()
        agent.say(#"""
            {"jsonrpc":"2.0","id":"perm-1","method":"session/request_permission","params":{"sessionId":"s1",
             "toolCall":{"toolCallId":"t1","title":"rm build"},
             "options":[{"optionId":"a","name":"Allow","kind":"allow_once"},{"optionId":"b","name":"Always","kind":"allow_always"},
                        {"optionId":"c","name":"Reject","kind":"reject_once"}]}}
            """#)
        guard case .approval(let request) = try await replies.next() else { Issue.record("no approval"); return }
        #expect(request.summary == "rm build")
        #expect(request.canAlwaysAllow)
        try session.answer(request, decision: .allowAlways)
        let answer = await agent.next()
        #expect(answer.id as? String == "perm-1")
        #expect(answer.result["outcome"] as? [String: String] == ["outcome": "selected", "optionId": "b"])
        session.stop()
    }

    @Test func anInterruptCancelsThePromptAndDropsWhatFollowsIt() async throws {
        let agent = FakeAgent()
        let session = session(agent)
        await agent.handshake()
        var own = session.ownTurns.makeAsyncIterator()
        let reply = try session.ask("Long task")
        let prompt = await agent.next()
        agent.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Working"}}"#)
        var replies = reply.makeAsyncIterator()
        #expect(try await replies.next() == .text("Working"))
        session.interrupt()
        #expect(try await replies.next() == nil)
        let cancel = await agent.next()
        #expect(cancel.method == "session/cancel")
        agent.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":" still"}}"#)
        agent.answer(prompt, #"{"stopReason":"cancelled"}"#)
        // The late text belonged to the cancelled prompt: it starts no turn of the agent's own.
        agent.update(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Later news"}}"#)
        let turn = try #require(await own.next())
        #expect(try await collect(turn) == [.text("Later news")])
        session.stop()
    }

    @Test func switchesTheModelByNameThroughItsConfigOption() async throws {
        let agent = FakeAgent()
        let session = session(agent)
        var details = session.details.makeAsyncIterator()
        await agent.handshake()
        _ = await details.next()
        try session.setModel("opus")
        let request = await agent.next()
        #expect(request.method == "session/set_config_option")
        #expect(request.params["configId"] as? String == "model")
        #expect(request.params["value"] as? String == "opus")
        agent.answer(request, #"{"configOptions":\#(FakeAgent.options.replacingOccurrences(of: #""currentValue":"sonnet""#, with: #""currentValue":"opus""#))}"#)
        #expect(await details.next() == "Claude Opus · low thinking")
        #expect(throws: AgentFailure.self) { try session.setModel("gemini") }
        session.stop()
    }

    @Test func choosesTheConfiguredModelAndThinkingAsTheCallStarts() async {
        let agent = FakeAgent()
        let session = AcpSession(channel: agent, settings: .init(directory: "/work", preamble: nil, ownTurnQuiet: .seconds(1),
                                                                 model: "opus", thinking: "high"))
        await agent.handshake()
        let first = await agent.next()
        let second = await agent.next()
        #expect([first, second].map { $0.params["configId"] as? String } == ["model", "effort"])
        #expect([first, second].map { $0.params["value"] as? String } == ["opus", "high"])
        session.stop()
    }

    @Test func theAgentGoingAwayFailsTheTurnAsStopped() async throws {
        let agent = FakeAgent()
        let session = session(agent)
        await agent.handshake()
        let reply = try session.ask("Hi")
        _ = await agent.next()
        agent.close()
        await #expect(throws: AgentStopped.self) { _ = try await collect(reply) }
    }

    @Test func answersRequestsItDoesNotSupportWithAnError() async {
        let agent = FakeAgent()
        let session = session(agent)
        await agent.handshake()
        agent.say(#"{"jsonrpc":"2.0","id":9,"method":"fs/read_text_file","params":{"path":"/etc/hosts"}}"#)
        let answer = await agent.next()
        #expect((answer.object["error"] as? [String: Any])?["code"] as? Int == -32601)
        session.stop()
    }
}
