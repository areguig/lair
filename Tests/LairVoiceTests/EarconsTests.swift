import Testing
import LairCore
import LairVoice

@Suite struct EarconsTests {
    @Test func everyEarconIsShortSoftAndClickFree() {
        for earcon in Earcon.allCases {
            let samples = Earcons.samples(for: earcon)
            let seconds = Double(samples.count) / 24_000
            #expect(seconds >= 0.04 && seconds <= 0.4, "\(earcon)")
            #expect((samples.map { abs($0) }.max() ?? 1) <= 0.3, "\(earcon)")
            #expect(abs(samples.first ?? 1) < 0.01 && abs(samples.last ?? 1) < 0.01, "\(earcon)")
        }
    }

    @Test func earconsAreDistinct() {
        let all = Earcon.allCases.map { Earcons.samples(for: $0) }
        for i in all.indices { for j in all.indices where j > i { #expect(all[i] != all[j]) } }
    }
}

@Suite struct SoundGroupTests {
    @Test func everyEarconBelongsToTheGroupItsSwitchNames() {
        #expect([Earcon.listening, .sent, .yourTurn].allSatisfy { $0.group == .listening })
        #expect(Earcon.done.group == .done)
        #expect(Earcon.needsYou.group == .needsYou)
        #expect(Earcon.problem.group == .problems)
    }

    @Test func eachGroupPreviewsWithASoundOfItsOwn() {
        for group in SoundGroup.allCases { #expect(group.preview.group == group) }
    }
}
