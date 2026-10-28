import LairCore
import Testing

struct AddressingTests {
    private let names = ["Claude", "Echo"]

    @Test func findsTheAgentNamedFirst() {
        let found = Addressing.split("Echo, check the backups.", names: names)
        #expect(found?.name == "Echo")
        #expect(found?.rest == "check the backups.")
    }

    @Test func ignoresCaseAndAGreeting() {
        #expect(Addressing.split("hey echo what's the weather", names: names)?.rest == "what's the weather")
        #expect(Addressing.split("Okay Claude. Run the tests", names: names)?.name == "Claude")
    }

    @Test func needsTheNameAloneAndSomethingAfterIt() {
        #expect(Addressing.split("Echoes fade in big rooms", names: names) == nil)
        #expect(Addressing.split("Echo.", names: names) == nil)
        #expect(Addressing.split("Ask Echo about it", names: names) == nil)
    }

    @Test func prefersTheLongestMatchingName() {
        let found = Addressing.split("Claude Code, fix the tests", names: ["Claude", "Claude Code"])
        #expect(found?.name == "Claude Code")
        #expect(found?.rest == "fix the tests")
    }

    @Test func ignoresEmptyNames() {
        #expect(Addressing.split(", hello", names: [""]) == nil)
    }
}
