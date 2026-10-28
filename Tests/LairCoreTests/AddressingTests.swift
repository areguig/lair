import LairCore
import Testing

struct AddressingTests {
    private let names = ["Claude", "Sage"]

    @Test func findsTheAgentNamedFirst() {
        let found = Addressing.split("Sage, check the backups.", names: names)
        #expect(found?.name == "Sage")
        #expect(found?.rest == "check the backups.")
    }

    @Test func ignoresCaseAndAGreeting() {
        #expect(Addressing.split("hey sage what's the weather", names: names)?.rest == "what's the weather")
        #expect(Addressing.split("Okay Claude. Run the tests", names: names)?.name == "Claude")
    }

    @Test func needsTheNameAloneAndSomethingAfterIt() {
        #expect(Addressing.split("Sages are hard to break", names: names) == nil)
        #expect(Addressing.split("Sage.", names: names) == nil)
        #expect(Addressing.split("Ask Sage about it", names: names) == nil)
    }
}
