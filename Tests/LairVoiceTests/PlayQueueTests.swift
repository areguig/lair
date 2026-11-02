import Testing
@testable import LairVoice

@Suite struct PlayQueueTests {
    @Test func theFirstBufferOnAnIdleQueueStartsAtOnce() {
        var queue = PlayQueue<Int>()
        #expect(queue.add(1) == 1)
    }

    @Test func laterBuffersStartOneByOneAsEachPrecedingOneEnds() {
        var queue = PlayQueue<Int>()
        #expect(queue.add(1) == 1)
        #expect(queue.add(2) == nil)
        #expect(queue.add(3) == nil)
        #expect(queue.finish() == 2)
        #expect(queue.finish() == 3)
        #expect(queue.finish() == nil)
    }

    @Test func aQueueThatRanDryStartsTheNextBufferAtOnce() {
        var queue = PlayQueue<Int>()
        _ = queue.add(1)
        #expect(queue.finish() == nil)
        #expect(queue.add(2) == 2)
    }

    @Test func clearingForgetsWhatWaitedAndWhatPlayed() {
        var queue = PlayQueue<Int>()
        _ = queue.add(1)
        _ = queue.add(2)
        queue.clear()
        #expect(queue.finish() == nil)
        #expect(queue.add(3) == 3)
    }
}
