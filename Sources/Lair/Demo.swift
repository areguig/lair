import AVFoundation
import LairCore
import LairVoice
import SwiftUI

/// `Lair --demo <folder>` renders the demo video from a script: someone's Mac on an ordinary afternoon, the real
/// Lair views, demo agents and the real on-device voices. It writes demo.mov (picture) and demo.wav (sound);
/// scripts/demo.sh joins them.
@MainActor enum Demo {
    static let fps = 30
    static let canvas = CGSize(width: 1280, height: 800)
    static let scale: CGFloat = 1.5
    static let you = "am_adam"
    static let agents = [
        AgentConfig(id: "claude", name: "Claude", kind: .claudeCode, voice: "af_heart", color: "#D97757", directory: "~/dev/app"),
        AgentConfig(id: "sage", name: "Sage", kind: .hermes, voice: "bf_emma", color: "#7B5CFF"),
        AgentConfig(id: "nova", name: "Nova", kind: .omp, voice: "af_nicole", color: "#3FB68B", directory: "~/dev/app"),
    ]

    // Where things are on the desktop, in points.
    static let menuIcon = CGPoint(x: canvas.width - 196, y: 14)
    static let floatingOrb = CGPoint(x: canvas.width - 92, y: canvas.height - 178)
    static let documentCaret = CGPoint(x: 640, y: 330)
    static let missionFrame = CGRect(x: 56, y: 50, width: 1060, height: 600)

    static func run(into folder: URL) async throws {
        let voice = VoiceModels()
        try await voice.load(warmUpVoice: you)
        let script = Script(voice: voice)
        try await story(script)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await writeVideo(script, to: folder.appending(path: "demo.mov"))
        try writeSound(script, to: folder.appending(path: "demo.wav"))
    }

    // The afternoon shown in the video. Indices are into `agents`.
    private static func story(_ s: Script) async throws {
        s.cursor(to: documentCaret, over: 0)
        s.type("# Lisbon weekend\n\n## Friday\n- Land 10:40, train to Cais do Sodré\n", over: 4.5)
        s.wait(3.2)

        s.caption("Ask without leaving what you're doing")
        s.keys("⌥ Space", for: 3.6)
        s.at { $0.calls[0].details = "claude-haiku-5-5" }
        try await s.you("Claude, the login test fails on main. Can you fix it?", to: 0)
        s.at { room in
            let claude = room.calls[0]
            claude.record(.thinking("A failing login test. Run it alone first, then read what it checks."))
            claude.record(.toolStarted(id: "t1", name: "Bash", input: "swift test --filter LoginTests"))
        }
        try await s.agent(0, says: "On it. I'll tell you when it's green.", after: 1.0)
        s.at { room in
            let claude = room.calls[0]
            claude.record(.toolFinished(id: "t1", output: "✘ testSignIn: token expired (fixtures/session.json)", failed: true))
            claude.record(.toolStarted(id: "t2", name: "Read", input: "Tests/Fixtures/session.json"))
            claude.record(.toolFinished(id: "t2", output: #"{ "token": "…", "expires": "2026-09-30" }"#, failed: false))
            claude.record(.thinking("The fixture's token expired last month. Make the expiry relative to now."))
            claude.record(.toolStarted(id: "t3", name: "Edit", input: "Tests/LoginTests.swift"))
            claude.record(.toolFinished(id: "t3", output: """
                @@ -12,3 +12,3 @@
                -    let session = try Fixture.load("session.json")
                +    let session = try Fixture.load("session.json").renewed(from: .now)
                """, failed: false))
            claude.state = .thinking
        }

        s.caption("Keep working; the orb floats on top")
        s.type("- Lunch at the market by the river\n\n## Saturday\n- Tram 28 early, before the crowds\n", over: 6)
        s.wait(5.4)

        s.caption("It asks before it acts")
        s.at { room in
            room.calls[0].pendingApproval = ApprovalRequest(id: "a1", tool: "Bash", summary: "Run the whole test suite")
            room.calls[0].log(.approval("Run the whole test suite"))
        }
        s.earcon(.needsYou)
        try await s.agent(0, says: "Claude needs your OK to run the whole test suite. Say yes, always, or no.",
                          after: 0.3, transcript: false, then: .waiting)
        s.keys("⌥ Space", for: 1.6)
        try await s.you("Yes.", to: 0, transcript: false)
        s.at { room in
            let claude = room.calls[0]
            claude.pendingApproval = nil
            claude.lines.append(.init(role: .info, text: "Allowed once: Run the whole test suite"))
            claude.log(.note("Allowed once: Run the whole test suite"))
            claude.record(.toolStarted(id: "t4", name: "Bash", input: "swift test"))
            claude.state = .thinking
        }
        s.type("- Sunset from the viewpoint in Graça\n", over: 2.4)
        s.wait(2.8)

        s.caption("Click the orb to talk to another agent")
        s.cursor(to: floatingOrb, over: 1.1)
        s.wait(1.2)
        s.click()
        s.at { $0.focusedID = "sage" }
        try await s.you("Sage, did last night's backups finish?", to: 1)
        s.click()
        s.at { room in
            let sage = room.calls[1]
            sage.record(.helper("delegate_task: check last night's backups"))
        }
        try await s.agent(1, says: "Yes. All three finished, and the newest one is from three this morning.", after: 1.8)
        s.at { room in
            let claude = room.calls[0]
            claude.record(.toolFinished(id: "t4", output: "Executed 214 tests, with 0 failures", failed: false))
            claude.logText("Fixed: the session fixture had expired. It now renews from today, and all 214 tests pass.")
            claude.record(.usage(inputTokens: 24_800, outputTokens: 640, cost: 0.027))
            claude.log(.timing(heard: 130, firstWord: 1_650, firstSound: 2_140, total: 41_300))
            claude.lines.append(.init(role: .agent, text: "Fixed: the session fixture had expired. All 214 tests pass."))
            claude.state = .ready
            claude.unread = true
        }
        s.earcon(.done)
        s.wait(0.8)

        s.caption("The whole room, one click away")
        s.cursor(to: menuIcon, over: 1.2)
        s.wait(1.3)
        s.click()
        s.show(.panel)
        s.at { room in
            room.focusedID = "claude"
            room.calls[0].unread = false
        }
        s.wait(4.2)
        s.cursor(to: documentCaret, over: 1.0)
        s.wait(0.6)
        s.click()
        s.hide(.panel)
        s.wait(0.6)

        s.caption("Several agents at once")
        s.keys("⌥ Space", for: 3.4)
        s.at { $0.focusedID = "nova"; $0.calls[2].details = "gpt-6-luna · low thinking" }
        try await s.you("Nova, clear out the old build caches.", to: 2)
        s.at { room in
            let nova = room.calls[2]
            nova.record(.toolStarted(id: "n1", name: "bash", input: "du -sh ~/Library/Caches/app-build/*"))
            nova.record(.toolFinished(id: "n1", output: "3.1G  derived\n1.1G  modules\n 40M  logs", failed: false))
            nova.logText("There are 4.2 GB of old build caches.")
            nova.pendingApproval = ApprovalRequest(id: "n2", tool: "bash", summary: "Delete 4.2 GB of old build caches")
            nova.log(.approval("Delete 4.2 GB of old build caches"))
        }
        s.earcon(.needsYou)
        try await s.agent(2, says: "There are four gigabytes of old caches. Nova needs your OK to delete them.",
                          after: 1.6, transcript: false, then: .waiting)

        s.caption("⌥⌘L: every agent's whole stream")
        s.keys("⌥ ⌘ L", for: 1.4)
        s.wait(0.5)
        s.show(.missionControl)
        s.wait(3.4)
        s.caption("Approve with a click")
        s.cursor(to: CGPoint(x: missionFrame.maxX - 100, y: missionFrame.maxY - 108), over: 1.3)
        s.wait(1.5)
        s.click()
        s.at { room in
            let nova = room.calls[2]
            nova.pendingApproval = nil
            nova.log(.note("Allowed once: Delete 4.2 GB of old build caches"))
            nova.record(.toolStarted(id: "n3", name: "bash", input: "rm -rf ~/Library/Caches/app-build/*"))
            nova.record(.toolFinished(id: "n3", output: "", failed: false))
            nova.lines.append(.init(role: .info, text: "Allowed once: Delete 4.2 GB of old build caches"))
            nova.state = .thinking
        }
        try await s.agent(2, says: "Done. You have four more gigabytes free.", after: 1.2)
        s.wait(1.8)

        s.caption(nil)
        s.show(.endCard)
        s.wait(4.5)
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
            guard let image = render(script, at: time), let pool = adaptor.pixelBufferPool,
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

    /// `Lair --demo-frame <seconds> out.png`: one still, to check a scene without rendering the video.
    static func writeFrame(at time: Double, to url: URL) async throws {
        let voice = VoiceModels()
        try await voice.load(warmUpVoice: you)
        let script = Script(voice: voice)
        try await story(script)
        print(script.outline)
        guard let image = render(script, at: time) else { return }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    private static let window = NSWindow(contentRect: NSRect(origin: .zero, size: missionFrame.size),
                                         styleMask: [.borderless], backing: .buffered, defer: false)

    private static func render(_ script: Script, at time: Double) -> CGImage? {
        let room = script.room(at: time), stage = script.stage(at: time)
        let mission = stage.open[.missionControl] == nil ? nil : missionControl(room, at: time)
        let renderer = ImageRenderer(content: DemoFrame(room: room, stage: stage, mission: mission,
                                                        caption: script.caption(at: time), time: time))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// ImageRenderer leaves scroll views blank, so Mission Control's streams go through a hidden window.
    /// A fresh hosting view each frame keeps SwiftUI from animating between frames in real time.
    private static func missionControl(_ room: Room, at time: Double) -> CGImage? {
        let view = NSHostingView(rootView: MissionControl(room: room).environment(\.renderTime, time))
        view.frame = NSRect(origin: .zero, size: missionFrame.size)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
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

/// What's on the desktop at one moment, besides the room: the cursor, the open windows, the typed text.
struct Stage {
    enum Window { case panel, missionControl, endCard }

    var cursor = CGPoint.zero
    /// Seconds since the last click, for its ripple.
    var sinceClick: Double?
    /// Seconds each window has been open.
    var open: [Window: Double] = [:]
    var document = ""
    var keys: String?
}

/// Builds the demo's timeline: room changes, desktop changes, captions and sounds placed on one track.
@MainActor final class Script {
    static let sampleRate = 24_000.0

    private(set) var time = 0.0
    private(set) var audio: [Float] = []
    private var steps: [(at: Double, apply: (Room) -> Void)] = []
    private var captions: [(at: Double, text: String?)] = []
    /// Agent lines that appear word by word while they are spoken.
    private var reveals: [(call: Int, start: Double, end: Double, text: String)] = []
    private var moves: [(start: Double, end: Double, to: CGPoint)] = []
    private var clicks: [Double] = []
    private var windows: [(at: Double, window: Stage.Window, open: Bool)] = []
    private var typing: [(start: Double, end: Double, text: String)] = []
    private var keyPresses: [(start: Double, end: Double, keys: String)] = []
    private let voice: VoiceModels

    init(voice: VoiceModels) {
        self.voice = voice
    }

    func wait(_ seconds: Double) { time += seconds }
    func at(_ apply: @escaping (Room) -> Void) { steps.append((time, apply)) }
    func caption(_ text: String?) { captions.append((time, text)) }
    func cursor(to point: CGPoint, over seconds: Double) { moves.append((time, time + seconds, point)) }
    func show(_ window: Stage.Window) { windows.append((time, window, true)) }
    func hide(_ window: Stage.Window) { windows.append((time, window, false)) }
    /// Text typed into the document from now on; the script carries on meanwhile.
    func type(_ text: String, over seconds: Double) { typing.append((time, time + seconds, text)) }
    /// A key chord shown on screen from now on, while the script carries on.
    func keys(_ keys: String, for seconds: Double) { keyPresses.append((time, time + seconds, keys)) }

    func click() {
        clicks.append(time)
        place(Self.click, at: time)
    }

    func earcon(_ earcon: Earcon) {
        place(Earcons.samples(for: earcon, sampleRate: Self.sampleRate).map { $0 * 0.6 }, at: time)
    }

    func you(_ text: String, to call: Int, transcript: Bool = true) async throws {
        let samples = try await voice.speech(for: text, voice: Demo.you)
        at { room in
            room.calls[call].state = .listening
            room.focusedID = Demo.agents[call].id
        }
        earcon(.listening)
        time += 0.25
        time += place(samples, at: time) + 0.2
        earcon(.sent)
        at { room in
            if transcript {
                room.calls[call].lines.append(.init(role: .you, text: text))
                room.calls[call].log(.you(text))
            }
            room.calls[call].state = transcript ? .thinking : room.calls[call].pendingApproval == nil ? .ready : .waiting
        }
    }

    func agent(_ call: Int, says text: String, after thinking: Double, transcript: Bool = true,
               then end: Call.State = .ready) async throws {
        if end != .waiting { at { $0.calls[call].state = .thinking } }
        time += thinking
        let samples = try await voice.speech(for: text, voice: Demo.agents[call].voice)
        at { room in
            room.calls[call].state = .speaking
            if transcript {
                room.calls[call].lines.append(.init(role: .agent, text: text))
                room.calls[call].logText(text)
            }
        }
        let duration = place(samples, at: time)
        if transcript { reveals.append((call, time, time + duration, text)) }
        time += duration + 0.35
        at { $0.calls[call].state = end }
    }

    /// Adds a clip to the sound track; returns its length in seconds.
    @discardableResult private func place(_ samples: [Float], at time: Double) -> Double {
        let start = Int(time * Self.sampleRate)
        if audio.count < start + samples.count { audio += Array(repeating: 0, count: start + samples.count - audio.count) }
        for (offset, sample) in samples.enumerated() { audio[start + offset] += sample }
        return Double(samples.count) / Self.sampleRate
    }

    /// A soft trackpad click: a short decaying tick.
    private static let click: [Float] = (0..<Int(0.025 * sampleRate)).map { i in
        let t = Double(i) / sampleRate
        return Float(sin(2 * .pi * 2_400 * t) * exp(-t * 260) * 0.18)
    }

    /// When each caption starts, to pick stills with `--demo-frame`.
    var outline: String {
        (captions.map { String(format: "%5.1f s  %@", $0.at, $0.text ?? "(none)") }
            + [String(format: "%5.1f s  end", time)]).joined(separator: "\n")
    }

    func caption(at time: Double) -> String? {
        captions.last { $0.at <= time }?.text
    }

    func stage(at time: Double) -> Stage {
        var stage = Stage()
        for move in moves where move.start <= time {
            let progress = move.end > move.start ? min(1, (time - move.start) / (move.end - move.start)) : 1
            let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
            let from = stage.cursor
            stage.cursor = CGPoint(x: from.x + (move.to.x - from.x) * eased, y: from.y + (move.to.y - from.y) * eased)
        }
        stage.sinceClick = clicks.last { $0 <= time }.map { time - $0 }
        for change in windows where change.at <= time {
            stage.open[change.window] = change.open ? time - change.at : nil
        }
        for typed in typing where typed.start <= time {
            let progress = min(1, (time - typed.start) / (typed.end - typed.start))
            stage.document += typed.text.prefix(Int(Double(typed.text.count) * progress))
        }
        stage.keys = keyPresses.last { $0.start <= time && time < $0.end }?.keys
        return stage
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

/// One frame of the video: a Mac desktop with a document being written, Lair's floating orb, its panel and
/// Mission Control when open, the cursor and the caption.
private struct DemoFrame: View {
    let room: Room
    let stage: Stage
    let mission: CGImage?
    let caption: String?
    let time: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
            DocumentWindow(text: stage.document, time: time)
                .frame(width: 760, height: 520)
                .offset(x: 150, y: 92)
            Dock()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)
            if let opened = stage.open[.missionControl], let mission {
                Image(decorative: mission, scale: 2)
                    .resizable()
                    .frame(width: Demo.missionFrame.width, height: Demo.missionFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) { TrafficLights().padding(14) }
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 18)
                    .offset(x: Demo.missionFrame.minX, y: Demo.missionFrame.minY)
                    .appearing(opened)
            }
            // Above every window, as the real one floats.
            if let call = room.focused, room.calls.contains(where: \.inCall) {
                Orb(color: Color(hex: call.agent.color), state: call.state, meter: room.meter(for: call))
                    .frame(width: 52, height: 52)
                    .position(Demo.floatingOrb)
            }
            menuBar
            if let opened = stage.open[.panel] {
                RoomView(room: room)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.55), radius: 30, y: 12)
                    .offset(x: Demo.menuIcon.x - 170, y: 34)
                    .appearing(opened)
            }
            if let keys = stage.keys {
                KeyCaps(keys: keys)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: Demo.canvas.height - 190)
            }
            if let caption, stage.open[.endCard] == nil {
                Text(caption)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: Demo.canvas.height - 138)
            }
            Cursor(sinceClick: stage.sinceClick)
                .offset(x: stage.cursor.x, y: stage.cursor.y)
            if let opened = stage.open[.endCard] {
                EndCard().appearing(opened, duration: 0.6)
            }
        }
        .frame(width: Demo.canvas.width, height: Demo.canvas.height, alignment: .topLeading)
        .clipped()
        .environment(\.renderTime, time)
        .environment(\.colorScheme, .dark)
    }

    /// A slow dusk, drifting a little so the desktop feels alive, with a fine grain so the gradient doesn't band.
    private var wallpaper: some View {
        let drift = Float(sin(time * 0.15) * 0.06)
        return ZStack {
            mesh(drift)
            Image(decorative: Self.grain, scale: 2)
                .resizable(resizingMode: .tile)
                .opacity(0.035)
        }
    }

    /// Gray noise from a fixed seed, so every render of the video is the same.
    private static let grain: CGImage = {
        let size = 256
        var seed: UInt32 = 0x2545F491
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let value = UInt8(seed >> 24)
            pixels[i * 4] = value; pixels[i * 4 + 1] = value; pixels[i * 4 + 2] = value
        }
        let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()

    private func mesh(_ drift: Float) -> some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.45 + drift, 0.55 - drift], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            Color(red: 0.12, green: 0.15, blue: 0.38), Color(red: 0.36, green: 0.22, blue: 0.52), Color(red: 0.62, green: 0.32, blue: 0.48),
            Color(red: 0.10, green: 0.24, blue: 0.46), Color(red: 0.78, green: 0.42, blue: 0.42), Color(red: 0.95, green: 0.62, blue: 0.42),
            Color(red: 0.06, green: 0.10, blue: 0.24), Color(red: 0.34, green: 0.20, blue: 0.40), Color(red: 0.88, green: 0.50, blue: 0.36),
        ])
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text("Writer").fontWeight(.semibold)
            ForEach(["File", "Edit", "Format", "View", "Window", "Help"], id: \.self) { Text($0) }
            Spacer()
            MenuBarIcon(room: room)
                .foregroundStyle(.white)
                .frame(width: 28, height: 22)
                .background(stage.open[.panel] == nil ? .clear : .white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
            // Fixed width, so the Lair icon sits exactly at Demo.menuIcon.
            HStack(spacing: 18) {
                Image(systemName: "battery.75percent")
                Image(systemName: "wifi")
                Text("Sat 3:42 PM")
            }
            .frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.leading, 18).padding(.trailing, 14)
        .frame(width: Demo.canvas.width, height: 28)
        .background(.black.opacity(0.22))
    }
}

private extension View {
    /// Fades and settles in over its first moments.
    func appearing(_ elapsed: Double, duration: Double = 0.22) -> some View {
        let progress = min(1, elapsed / duration)
        return opacity(progress).scaleEffect(0.97 + 0.03 * progress, anchor: .top)
    }
}

/// A plain writing app: the user's own work, untouched by Lair.
private struct DocumentWindow: View {
    let text: String
    let time: Double

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Lisbon weekend.md").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.7))
                TrafficLights().frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            }
            .frame(height: 38)
            .background(Color(white: 0.93))
            Rectangle().fill(Color(white: 0.84)).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    styled(line, last: index == lines.count - 1)
                }
                Spacer()
            }
            .padding(.horizontal, 56).padding(.vertical, 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.985))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.18)))
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
        .environment(\.colorScheme, .light)
    }

    private var lines: [String] { text.components(separatedBy: "\n") }

    private func styled(_ line: String, last: Bool) -> some View {
        let caret = last && Int(time * 2) % 2 == 0 ? "▍" : ""
        let (body, font): (String, Font) = if line.hasPrefix("## ") {
            (String(line.dropFirst(3)), .system(size: 20, weight: .semibold, design: .serif))
        } else if line.hasPrefix("# ") {
            (String(line.dropFirst(2)), .system(size: 30, weight: .bold, design: .serif))
        } else if line.hasPrefix("- ") {
            ("•  " + line.dropFirst(2), .system(size: 17, design: .serif))
        } else {
            (line, .system(size: 17, design: .serif))
        }
        return (Text(body) + Text(caret).foregroundStyle(Color.accentColor))
            .font(font)
            .foregroundStyle(.black.opacity(0.82))
            .frame(minHeight: 8, alignment: .leading)
    }
}

private struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                     Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { color in
                Circle().fill(color).frame(width: 12, height: 12)
            }
        }
    }
}

/// A Dock of generic apps, with Lair's own icon among them.
private struct Dock: View {
    private let apps: [(String, [Color])] = [
        ("folder.fill", [.blue, .cyan]), ("globe", [.indigo, .blue]), ("envelope.fill", [.blue, .teal]),
        ("calendar", [.red, .orange]), ("music.note", [.pink, .red]), ("photo.fill", [.orange, .yellow]),
        ("doc.text.fill", [.gray, .white]), ("terminal.fill", [.black, .gray]),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(apps, id: \.0) { symbol, colors in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .overlay(Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(.white))
                    .frame(width: 52, height: 52)
            }
            Divider().frame(height: 44).overlay(.white.opacity(0.3))
            AppIcon()
                .frame(width: 1024, height: 1024)
                .scaleEffect(52.0 / 1024)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(8)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.25)))
    }
}

/// The keys being pressed, shown the way screencasts do.
private struct KeyCaps: View {
    let keys: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(keys.split(separator: " ").map(String.init), id: \.self) { key in
                Text(key)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 46, minHeight: 46)
                    .padding(.horizontal, key.count > 1 ? 14 : 0)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.25)))
            }
        }
    }
}

private struct Cursor: View {
    let sinceClick: Double?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let sinceClick, sinceClick < 0.4 {
                Circle()
                    .strokeBorder(.white.opacity(0.8 * (1 - sinceClick / 0.4)), lineWidth: 2)
                    .frame(width: 18 + sinceClick * 70, height: 18 + sinceClick * 70)
                    .offset(x: -(9 + sinceClick * 35), y: -(9 + sinceClick * 35))
            }
            Image(systemName: "cursorarrow")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.black)
                .background(Image(systemName: "cursorarrow").font(.system(size: 24, weight: .black)).foregroundStyle(.white))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .offset(x: -5, y: -3)
        }
    }
}

private struct EndCard: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.035, blue: 0.05)
            RadialGradient(colors: [Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.25), .clear], center: .center,
                           startRadius: 0, endRadius: 520)
            VStack(spacing: 20) {
                AppIcon()
                    .frame(width: 1024, height: 1024)
                    .scaleEffect(120.0 / 1024)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                Text("Lair").font(.system(size: 64, weight: .bold, design: .rounded))
                Text("Talk to your coding agents while you get on with your day.\nAll speech stays on your Mac.")
                    .font(.system(size: 22, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
        }
        .frame(width: Demo.canvas.width, height: Demo.canvas.height)
    }
}
