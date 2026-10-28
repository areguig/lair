import LairVoice
import SwiftUI

/// The agent's avatar: a glowing orb that breathes when idle, follows your voice, swirls while thinking
/// and pulses with its own voice.
struct Orb: View {
    let color: Color
    let state: Call.State
    var meter: LevelMeter?
    @State private var smoothed = Smoothed()
    @Environment(\.renderTime) private var renderTime

    var body: some View {
        TimelineView(.animation(paused: state == .offline)) { timeline in
            let time = renderTime ?? timeline.date.timeIntervalSinceReferenceDate
            let level = renderTime == nil ? smoothed.next(Double(meter?.level ?? 0)) : Double(meter?.level ?? 0)
            let scale = scale(time: time, level: level)
            ZStack {
                Circle()
                    .fill(EllipticalGradient(colors: [color.opacity(0.55), .clear], center: .center,
                                             startRadiusFraction: 0, endRadiusFraction: 0.5))
                    .scaleEffect(1.5 + level * 0.5)
                    .blur(radius: 18)
                    .opacity(state == .offline ? 0 : 0.9)
                core(time: time)
                    .scaleEffect(scale)
            }
            .saturation(state == .offline ? 0.25 : 1)
            .opacity(state == .offline ? 0.6 : 1)
        }
        .animation(.smooth(duration: 0.5), value: state)
    }

    /// Soft clouds of light and shade drifting inside the sphere, like a sky seen through a marble.
    private func core(time: Double) -> some View {
        let phase = time * spinSpeed / 60
        return GeometryReader { geometry in
            let size = geometry.size.width
            ZStack {
                Circle().fill(LinearGradient(colors: [color.mix(with: .white, by: 0.25), color,
                                                      color.mix(with: .black, by: 0.3)],
                                             startPoint: .top, endPoint: .bottom))
                cloud(.white.opacity(0.75), size: size * 0.62, orbit: size * 0.2, phase: phase, blur: size * 0.12)
                cloud(color.mix(with: .pink, by: 0.45), size: size * 0.7, orbit: size * 0.24, phase: -phase * 0.8 + 2,
                      blur: size * 0.14)
                cloud(color.mix(with: .indigo, by: 0.5).opacity(0.8), size: size * 0.55, orbit: size * 0.26,
                      phase: phase * 0.6 + 4, blur: size * 0.12)
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
    }

    private func cloud(_ fill: Color, size: Double, orbit: Double, phase: Double, blur: Double) -> some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .offset(x: cos(phase) * orbit, y: sin(phase * 1.3) * orbit)
            .blur(radius: blur)
    }

    private var spinSpeed: Double {
        switch state {
        case .offline: 0
        case .ready: 20
        case .listening: 60
        case .thinking: 160
        case .speaking: 45
        case .waiting: 12
        }
    }

    private func scale(time: Double, level: Double) -> Double {
        switch state {
        case .offline: 0.86
        case .ready: 1 + sin(time * 1.6) * 0.025
        case .listening, .speaking: 0.96 + level * 0.28
        case .thinking: 0.94 + sin(time * 5) * 0.03
        // A slow, deliberate pulse: it's your turn.
        case .waiting: 0.97 + (sin(time * 2.4) + 1) * 0.04
        }
    }

    /// Eases the meter so the orb swells and settles instead of flickering.
    final class Smoothed {
        private var value = 0.0
        func next(_ target: Double) -> Double {
            value += (target - value) * (target > value ? 0.35 : 0.12)
            return value
        }
    }
}

extension Color {
    /// `#RRGGBB`; anything else falls back to gray.
    init(hex: String) {
        let digits = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x808080
        self.init(red: Double((digits >> 16) & 0xFF) / 255, green: Double((digits >> 8) & 0xFF) / 255,
                  blue: Double(digits & 0xFF) / 255)
    }
}
