/// Which queued buffer is playing, so something can happen the moment each one starts.
struct PlayQueue<Item> {
    private var waiting: [Item] = []
    private var playing = false

    /// The item to start now: this one if nothing is playing, else it waits its turn and the result is nil.
    mutating func add(_ item: Item) -> Item? {
        guard playing else {
            playing = true
            return item
        }
        waiting.append(item)
        return nil
    }

    /// The playing buffer ended: the item that starts now, nil when the queue ran dry.
    mutating func finish() -> Item? {
        guard !waiting.isEmpty else {
            playing = false
            return nil
        }
        return waiting.removeFirst()
    }

    mutating func clear() {
        waiting = []
        playing = false
    }
}
