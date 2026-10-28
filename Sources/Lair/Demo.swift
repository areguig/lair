import AVFoundation
import LairCore
import LairVoice
import SwiftUI

/// `Lair --demo <folder>` renders the demo video from a scripted call: the real panel, demo agents and the real
/// on-device voices. It writes demo.mov (picture) and demo.wav (sound); scripts/demo.sh joins them.
@MainActor enum Demo {
    static let fps = 30
    static let canvas = CGSize(width: 1280, height: 800)
    static let scale: CGFloat = 1.5
    static let you = "am_adam"
    static let agents = [
        AgentConfig(id: "claude", name: "Claude", kind: .claudeCode, voice: "af_heart", color: "#D97757", directory: "~/dev/app"),
        AgentConfig(id: "sage", name: "Sage", kind: .hermes, voice: "bf_emma", color: "#7B5CFF"),
        AgentConfig(id: "copilot", name: "Copilot", kind: .omp, voice: "am_michael", color: "#3FB68B", directory: "~"),
    ]

    static func run(into folder: URL) async throws {
        let voice = VoiceModels()
        try await voice.load(warmUpVoice: you)
        let script = Script(voice: voice)
        try await story(script)
        script.wait(1.5)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await writeVideo(script, to: folder.appending(path: "demo.mov"))
        try writeSound(script, to: folder.appending(path: "demo.wav"))
    }

    // The call shown in the video. Indices are into `agents`.
    private static func story(_ s: Script) async throws {
        s.caption("Your agents live in the menu bar")
        s.wait(2.2)

        s.caption("Hold ⌥Space and talk")
        s.at { $0.calls[0].state = .ready; $0.calls[0].details = "claude-haiku-5-5" }
        s.wait(0.6)
        try await s.you("What's left before we ship the release?", to: 0)
        try await s.agent(0, says: "Two things. The changelog still needs the voice section, and the build number "
            + "hasn't been bumped. Want me to do both?", after: 1.1)

        try await s.you("Yes, go ahead.", to: 0)
        s.caption("It asks before it acts")
        s.wait(1.2)
        s.at {
            $0.calls[0].pendingApproval = ApprovalRequest(
                id: "demo", tool: "Bash", summary: "Bump the build number in Info.plist and commit it",
                suggestions: Data(#"[{"type":"addRules"}]"#.utf8))
        }
        try await s.agent(0, says: "Claude needs your OK to bump the build number in Info.plist and commit it. "
            + "Say yes, always, or no.", after: 0, transcript: false, then: .waiting)
        s.caption("Answer by voice, notification or click")
        try await s.you("Always.", to: 0, transcript: false)
        s.at {
            $0.calls[0].pendingApproval = nil
            $0.calls[0].lines.append(.init(role: .notice, text: "Always allowed: Bump the build number in Info.plist and commit it"))
        }
        try await s.agent(0, says: "Done. The changelog is updated, and the build number is bumped and committed.",
                          after: 1.6)

        s.caption("Several agents, one at a time on the floor")
        try await s.you("Sage, did last night's backups finish?", to: 0, transcript: false)
        s.at {
            $0.focusedID = "sage"
            $0.calls[1].state = .thinking
            $0.calls[1].lines.append(.init(role: .you, text: "did last night's backups finish?"))
        }
        try await s.agent(1, says: "Yes. All three finished, and the newest one is from three this morning.", after: 2.2)

        s.caption("All speech stays on your Mac")
        s.wait(2.8)
    }

    // MARK: - Rendering

    private static func writeVideo(_ script: Script, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = Int(canvas.width * scale), height = Int(canvas.height * scale)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frames = Int(script.time * Double(fps))
        for frame in 0..<frames {
            let time = Double(frame) / Double(fps)
            let renderer = ImageRenderer(content: DemoFrame(room: script.room(at: time), caption: script.caption(at: time),
                                                            time: time))
            renderer.scale = scale
            guard let image = renderer.cgImage, let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: image, pool: pool)
            else { continue }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
            if frame % (fps * 5) == 0 { print("frame \(frame)/\(frames)") }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    private static func writeSound(_ script: Script, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        var samples = script.audio
        samples += Array(repeating: 0, count: max(0, Int(script.time * Script.sampleRate) - samples.count))
        let format = AVAudioFormat(standardFormatWithSampleRate: Script.sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }
}

/// Builds the demo's timeline: room changes, captions and voices placed on one sound track.
@MainActor final class Script {
    static let sampleRate = 24_000.0

    private(set) var time = 0.0
    private(set) var audio: [Float] = []
    private var steps: [(at: Double, apply: (Room) -> Void)] = []
    private var captions: [(at: Double, text: String)] = []
    /// Agent lines that appear word by word while they are spoken.
    private var reveals: [(call: Int, start: Double, end: Double, text: String)] = []
    private let voice: VoiceModels

    init(voice: VoiceModels) {
        self.voice = voice
    }

    func wait(_ seconds: Double) { time += seconds }
    func at(_ apply: @escaping (Room) -> Void) { steps.append((time, apply)) }
    func caption(_ text: String) { captions.append((time, text)) }

    func you(_ text: String, to call: Int, transcript: Bool = true) async throws {
        let samples = try await voice.speech(for: text, voice: Demo.you)
        at { $0.calls[call].state = .listening }
        time += place(samples) + 0.2
        at { room in
            if transcript { room.calls[call].lines.append(.init(role: .you, text: text)) }
            room.calls[call].state = transcript ? .thinking : room.calls[call].pendingApproval == nil ? .ready : .waiting
        }
    }

    func agent(_ call: Int, says text: String, after thinking: Double, transcript: Bool = true,
               then end: Call.State = .ready) async throws {
        at { $0.calls[call].state = .thinking }
        time += thinking
        let samples = try await voice.speech(for: text, voice: Demo.agents[call].voice)
        at { room in
            room.calls[call].state = .speaking
            if transcript { room.calls[call].lines.append(.init(role: .agent, text: text)) }
        }
        let duration = place(samples)
        if transcript { reveals.append((call, time, time + duration, text)) }
        time += duration + 0.35
        at { $0.calls[call].state = end }
    }

    /// Adds a clip to the sound track at the current time; returns its length in seconds.
    private func place(_ samples: [Float]) -> Double {
        let start = Int(time * Self.sampleRate)
        if audio.count < start + samples.count { audio += Array(repeating: 0, count: start + samples.count - audio.count) }
        for (offset, sample) in samples.enumerated() { audio[start + offset] += sample }
        return Double(samples.count) / Self.sampleRate
    }

    func caption(at time: Double) -> String? {
        captions.last { $0.at <= time }?.text
    }

    func room(at time: Double) -> Room {
        let room = Room(config: LairConfig(agents: Demo.agents))
        room.readiness = .ready
        for step in steps where step.at <= time { step.apply(room) }
        for reveal in reveals where reveal.start <= time && time < reveal.end {
            let call = room.calls[reveal.call]
            guard let index = call.lines.lastIndex(where: { $0.role == .agent && $0.text == reveal.text }) else { continue }
            let words = reveal.text.split(separator: " ")
            let shown = Int((Double(words.count) * (time - reveal.start) / (reveal.end - reveal.start)).rounded(.up))
            call.lines[index].text = words.prefix(max(1, shown)).joined(separator: " ")
        }
        let meter = LevelMeter()
        let window = Int(0.03 * Script.sampleRate)
        let center = Int(time * Script.sampleRate)
        if center - window >= 0, center + window < audio.count {
            meter.set(LevelMeter.rms(Array(audio[(center - window)..<(center + window)])))
        }
        room.meterOverride = meter
        return room
    }
}

/// One frame of the video: a desktop with a menu bar, the open Lair panel, and the caption.
private struct DemoFrame: View {
    let room: Room
    let caption: String?
    let time: Double

    var body: some View {
        let tint = Color(hex: room.focused?.agent.color ?? "#D97757")
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.11, green: 0.08, blue: 0.17), Color(red: 0.03, green: 0.04, blue: 0.07)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [tint.opacity(0.22), .clear], center: UnitPoint(x: 0.22, y: 0.75),
                           startRadius: 0, endRadius: 620)
            menuBar
            VStack(alignment: .leading, spacing: 16) {
                Text("Lair")
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                Text("Talk to your coding agents by voice.\nSpeech in and out stays on your Mac.")
                    .font(.system(size: 24, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineSpacing(4)
                if let caption {
                    Text(caption)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(tint.mix(with: .white, by: 0.25), in: Capsule())
                        .padding(.top, 26)
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 96)
            .padding(.top, 250)
            RoomView(room: room)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
                .offset(x: Demo.canvas.width - 340 - 110, y: 38)
        }
        .frame(width: Demo.canvas.width, height: Demo.canvas.height)
        .environment(\.renderTime, time)
        .environment(\.colorScheme, .dark)
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text("Finder").fontWeight(.semibold)
            Spacer()
            Image(systemName: "waveform.circle.fill").foregroundStyle(.white)
            Image(systemName: "wifi")
            Text("Wed 3:42 PM")
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 18)
        .frame(width: Demo.canvas.width, height: 28)
        .background(.black.opacity(0.35))
    }
}
