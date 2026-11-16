import LairCore
import Testing

struct AgentDetailsTests {
    @Test func namesTheModelAndHowMuchItThinks() {
        #expect(agentDetails(model: "gpt-6-luna", thinking: "low") == "gpt-6-luna · low thinking")
        #expect(agentDetails(model: "gpt-6-luna", thinking: "off") == "gpt-6-luna")
        #expect(agentDetails(model: nil, thinking: nil) == nil)
    }

    @Test func aLevelThatAlreadySaysThinkingIsNotSaidTwice() {
        #expect(agentDetails(model: "qwen", thinking: "Thinking: medium") == "qwen · Thinking: medium")
    }
}
