import Foundation
import LairCore

public enum Earcon: CaseIterable, Sendable {
    case listening, sent, needsYou, done, problem
    /// The mic opened on its own for your reply: quieter than `listening`, since it follows every answer.
    case yourTurn

    /// The Settings switch that turns this sound off.
    public var group: SoundGroup {
        switch self {
        case .listening, .sent, .yourTurn: .listening
        case .done: .done
        case .needsYou: .needsYou
        case .problem: .problems
        }
    }
}

extension SoundGroup {
    /// The sound played to try the group out.
    public var preview: Earcon {
        switch self {
        case .listening: .listening
        case .done: .done
        case .needsYou: .needsYou
        case .problems: .problem
        }
    }
}

/// Short UI sounds synthesized in code, so there are no audio assets to ship.
public enum Earcons {
    public static func samples(for earcon: Earcon, sampleRate: Double = 24_000) -> [Float] {
        switch earcon {
        case .listening: render([(660, 0, 0.07, 0.16), (880, 0.07, 0.09, 0.16)], total: 0.16, rate: sampleRate)
        case .sent: render([(520, 0, 0.09, 0.2)], total: 0.09, rate: sampleRate, decay: 0.025)
        case .needsYou: render([(784, 0, 0.2, 0.17), (1047, 0.15, 0.2, 0.17)], total: 0.35, rate: sampleRate, decay: 0.09)
        case .done: render([(659, 0, 0.14, 0.17), (523, 0.13, 0.17, 0.17)], total: 0.3, rate: sampleRate, decay: 0.07)
        case .yourTurn: render([(988, 0, 0.09, 0.08)], total: 0.09, rate: sampleRate, decay: 0.04)
        case .problem: render([(165, 0, 0.11, 0.22), (147, 0.14, 0.14, 0.22)], total: 0.28, rate: sampleRate, decay: 0.05, overtone: 0.1)
        }
    }

    /// Notes are (frequency Hz, start s, length s, amplitude); each is a soft sine with a faint overtone.
    private static func render(
        _ notes: [(freq: Double, start: Double, length: Double, amp: Double)],
        total: Double, rate: Double, decay: Double = 0.12, overtone: Double = 0.2
    ) -> [Float] {
        var out = [Float](repeating: 0, count: Int(total * rate))
        let attack = 0.008, release = 0.02
        for note in notes {
            let first = Int(note.start * rate)
            let count = min(Int(note.length * rate), out.count - first)
            for i in 0..<count {
                let t = Double(i) / rate
                let rise = min(1, t / attack)
                let fade = min(1, Double(count - 1 - i) / rate / release)  // zero on the last sample, so no click
                let envelope = sin(rise * .pi / 2) * sin(rise * .pi / 2) * sin(fade * .pi / 2) * sin(fade * .pi / 2) * exp(-t / decay)
                let phase = 2 * Double.pi * note.freq * t
                out[first + i] += Float(note.amp * envelope * (sin(phase) + overtone * sin(2 * phase)))
            }
        }
        return out
    }
}
