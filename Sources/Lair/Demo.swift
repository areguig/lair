import AVFoundation
import LairCore
import LairVoice
import SwiftUI

/// `Lair --demo <folder>` renders the demo video from a script: a team of demo agents on a Mac, the real Lair
/// views and the real on-device voices. It writes demo.mov (picture) and demo.wav (sound); scripts/demo.sh joins them.
@MainActor enum Demo {
    static let fps = 30
    static let canvas = CGSize(width: 1280, height: 800)
    static let scale: CGFloat = 1.5
    static let you = "michael"
    static let agents = [
        AgentConfig(id: "atlas", name: "Atlas", preset: .claude, voice: Voices.defaultName(), color: "#D97757", directory: "~/dev/trips"),
        AgentConfig(id: "iris", name: "Iris", preset: .claude, voice: "jane", color: "#C566E0", directory: "~/dev/trips"),
        AgentConfig(id: "sage", name: "Sage", preset: .omp, voice: "vera", color: "#3FB68B", directory: "~/dev/trips"),
    ]

    // Where things are on the desktop, in points.
    static let menuIcon = CGPoint(x: canvas.width - 196, y: 14)
    static let floatingOrb = CGPoint(x: canvas.width - 92, y: canvas.height - 178)
    static let missionFrame = CGRect(x: 56, y: 50, width: 1060, height: 600)
    /// The panel is 424 × 580 pt: under the menu icon, kept inside the screen.
    static let panelOrigin = CGPoint(x: min(menuIcon.x - 212, canvas.width - 424 - 8), y: 34)
    static let panelFocus = CGPoint(x: panelOrigin.x + 212, y: 330)
    /// The agents in the panel's rail (the avatars down its left side), in agents order: 69 pt apart, measured from a frame.
    static let chips = (0..<3).map { CGPoint(x: panelOrigin.x + 47, y: panelOrigin.y + 86 + 69 * CGFloat($0)) }
    /// The Allow button of the approval card, with the one-line request Sage makes in the story.
    static let panelAllow = CGPoint(x: panelOrigin.x + 323, y: panelOrigin.y + 442)
    /// The middle of Mission Control's column `i`, at its `y`.
    static func column(_ i: Int, y: CGFloat) -> CGPoint {
        let width = (missionFrame.width - 14 * 4) / 3
        return CGPoint(x: missionFrame.minX + 14 + (width + 14) * CGFloat(i) + width / 2, y: y)
    }

    static func run(into folder: URL) async throws {
        let voice = VoiceModels()
        try await voice.load(warmUpVoice: you)
        let script = Script(voice: voice)
        try await story(script)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await writeVideo(script, to: folder.appending(path: "demo.mov"))
        try writeSound(script, to: folder.appending(path: "demo.wav"))
    }

    // The video. Indices are into `agents`.
    private static func story(_ s: Script) async throws {
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        s.cursor(to: CGPoint(x: 620, y: 440), over: 0)
        s.at { room in
            room.calls[0].details = "claude-sonnet-5"
            room.calls[1].details = "claude-haiku-5-5"
            room.calls[2].details = "gpt-6-luna · low thinking"
        }
        s.caption("Your coding agents, in the menu bar")
        s.wait(1.4)
        s.cursor(to: menuIcon, over: 1.0)
        s.wait(1.1)
        s.click()
        s.show(.panel)
        s.camera(to: panelFocus, zoom: 1.1, over: 0.9)
        s.wait(1.6)

        s.caption("Hold ⌥Space and ask")
        s.keys("⌥ Space", for: 3.2)
        try await s.you("Add rate limiting to the bookings API.", to: 0)
        s.at { room in
            room.calls[0].record(.thinking("Rate limiting per user. Find where bookings requests come in first."))
            room.calls[0].record(.toolStarted(id: "a1", name: "Grep", input: "router.post(\"/bookings\""))
        }
        try await s.agent(0, says: "On it. A token bucket per user, with tests.", after: 0.9, then: .thinking)

        s.caption("Several agents at once: click one to switch")
        s.cursor(to: chips[1], over: 0.8)
        s.wait(0.9)
        s.click()
        s.at { $0.focusedID = "iris" }
        s.wait(0.5)
        s.keys("⌥ Space", for: 3.4)
        try await s.you("Build the empty state for the trips screen.", to: 1)
        s.at { room in
            room.calls[1].record(.toolStarted(id: "i1", name: "Read", input: "Design/Tokens.swift"))
        }
        try await s.agent(1, says: "Sure. I'll use the illustration from the design kit.", after: 0.9, then: .thinking)

        s.caption("…or start with its name")
        s.keys("⌥ Space", for: 3.6)
        try await s.you("Sage, review Atlas's branch once it's pushed.", to: 2)
        try await s.agent(2, says: "Will do. I'll watch for the push.", after: 0.8, then: .thinking)

        s.caption("It asks before it acts")
        s.at { room in
            room.calls[2].pendingApproval = ApprovalRequest(id: "s1", tool: "bash",
                                                            summary: "Fetch and check out atlas/rate-limit")
            room.calls[2].log(.approval("bash: Fetch and check out atlas/rate-limit"))
        }
        s.earcon(.needsYou)
        try await s.agent(2, says: "Sage needs your OK to fetch and check out the rate limit branch. Allow it? "
            + "Say yes, always, or no.", after: 0.3, transcript: false, then: .waiting)
        s.cursor(to: panelAllow, over: 0.8)
        s.wait(0.9)
        s.click()
        s.at { room in
            let sage = room.calls[2]
            sage.pendingApproval = nil
            sage.lines.append(.init(role: .info, text: "Allowed once: Fetch and check out atlas/rate-limit"))
            sage.log(.note("Allowed once: Fetch and check out atlas/rate-limit"))
            sage.record(.toolStarted(id: "s2", name: "bash", input: "git fetch && git checkout atlas/rate-limit"))
            sage.state = .thinking
        }
        s.wait(1.2)

        s.caption("Close it; they keep working")
        s.cursor(to: CGPoint(x: 560, y: 420), over: 0.9)
        s.wait(0.9)
        s.click()
        s.hide(.panel)
        s.camera(to: center, zoom: 1, over: 0.9)
        s.wait(1.6)

        // The floating orb, up close: it talks to whoever is in focus, and follows a name.
        s.caption("The orb stays on screen during a call: click to talk")
        s.camera(to: floatingOrb, zoom: 2.6, over: 1.0)
        // On the orb's lower edge, so the pointer doesn't hide it.
        s.cursor(to: floatingOrb.applying(.init(translationX: 15, y: 17)), over: 1.2)
        s.wait(1.4)
        s.click()
        try await s.you("How's the review going?", to: 2)
        s.click()
        try await s.agent(2, says: "Halfway. One note so far: the refill should use a monotonic clock.", after: 1.1,
                          then: .thinking)
        s.wait(0.4)
        s.caption("Start with a name and the orb follows")
        s.click()
        try await s.you("Iris, are the snapshots done?", to: 1)
        s.click()
        try await s.agent(1, says: "Almost. I'm running the snapshot tests now.", after: 1.0, then: .thinking)
        s.wait(0.6)
        s.camera(to: center, zoom: 1, over: 0.9)
        s.cursor(to: CGPoint(x: 600, y: 430), over: 0.9)
        s.wait(1.0)

        s.caption("⌥⌘L: Mission Control")
        s.keys("⌥ ⌘ L", for: 1.4)
        s.wait(0.5)
        s.show(.missionControl)
        s.camera(to: CGPoint(x: missionFrame.midX, y: missionFrame.midY + 6), zoom: 1.13, over: 0.8)
        work(s)
        s.wait(3.5)
        s.caption("Every tool call, diff and test run, live")
        s.wait(5.5)

        s.caption("One finishes and calls out")
        s.at { room in
            let atlas = room.calls[0]
            atlas.record(.toolFinished(id: "a5", output: "Executed 86 tests, with 0 failures", failed: false))
            atlas.logText("Rate limiting is in: 20 requests a minute per user, with a test for the 429. All 86 tests pass.")
            atlas.record(.usage(inputTokens: 31_200, outputTokens: 1_480, cost: 0.041))
            atlas.log(.timing(heard: 120, firstWord: 1_580, firstSound: 2_060, total: 48_900))
            atlas.state = .ready
            atlas.unread = true
        }
        s.earcon(.done)
        s.wait(0.3)
        try await s.announce(0, "Atlas is done.")
        s.wait(0.8)

        // Iris is in focus since the orb scene, so Sage's request comes as a one-line call-out.
        s.at { room in
            let sage = room.calls[2]
            sage.pendingApproval = ApprovalRequest(id: "s9", tool: "bash", summary: "Post the review on the pull request")
            sage.log(.approval("bash: Post the review on the pull request"))
            sage.state = .waiting
            sage.unread = true
        }
        s.earcon(.needsYou)
        s.wait(0.3)
        try await s.announce(2, "Sage needs your OK.")
        s.caption("Approve with a click")
        s.cursor(to: column(2, y: missionFrame.maxY - 108).applying(.init(translationX: 80, y: 0)), over: 1.0)
        s.wait(1.1)
        s.click()
        s.at { room in
            let sage = room.calls[2]
            sage.pendingApproval = nil
            sage.unread = false
            sage.log(.note("Allowed once: Post the review on the pull request"))
            sage.record(.toolStarted(id: "s10", name: "bash", input: "gh pr review 128 --comment --body-file review.md"))
            sage.state = .thinking
        }
        s.wait(1.4)

        s.caption("Click an agent to hear what it did")
        s.cursor(to: column(0, y: missionFrame.minY + 92), over: 1.0)
        s.wait(1.1)
        s.click()
        s.at { room in
            room.focusedID = "atlas"
            room.calls[0].unread = false
        }
        try await s.agent(0, says: "Rate limiting is in: twenty requests a minute per user, with a test for the "
            + "four twenty nine. All eighty six tests pass.", after: 0, transcript: false)
        s.wait(1.2)

        s.caption(nil)
        s.show(.endCard)
        s.wait(4.5)
    }

    /// Everyone's work streaming into Mission Control at once, spread over the next few seconds.
    private static func work(_ s: Script) {
        s.after(0.4) { $0.calls[0].record(.toolFinished(id: "a1", output: "Sources/API/BookingsRouter.swift:41", failed: false)) }
        s.after(0.9) { $0.calls[1].record(.toolFinished(id: "i1", output: "spacing.l = 24, radius.card = 16, ink.muted", failed: false)) }
        s.after(1.3) { $0.calls[2].record(.toolFinished(id: "s2", output: "Switched to branch 'atlas/rate-limit'", failed: false)) }
        s.after(1.6) { room in
            room.calls[0].record(.toolStarted(id: "a2", name: "Write", input: "Sources/API/RateLimiter.swift"))
            room.calls[0].record(.toolFinished(id: "a2", output: """
                +struct RateLimiter {
                +    let perMinute = 20
                +    func allow(_ user: User.ID, at now: Date) -> Bool
                """, failed: false))
        }
        s.after(2.4) { room in
            room.calls[1].record(.thinking("No trips yet: a calm illustration, one line of copy, one button to plan a trip."))
            room.calls[1].record(.toolStarted(id: "i2", name: "Write", input: "Sources/Trips/TripsEmptyState.swift"))
        }
        s.after(3.0) { room in
            room.calls[2].record(.toolStarted(id: "s3", name: "bash", input: "git diff main --stat"))
            room.calls[2].record(.toolFinished(id: "s3", output: " Sources/API/BookingsRouter.swift |  6 +-\n Sources/API/RateLimiter.swift   | 38 +++", failed: false))
        }
        s.after(3.6) { room in
            room.calls[1].record(.toolFinished(id: "i2", output: """
                +struct TripsEmptyState: View {
                +    var body: some View { … }
                """, failed: false))
            room.calls[0].record(.toolStarted(id: "a3", name: "Edit", input: "Sources/API/BookingsRouter.swift"))
        }
        s.after(4.4) { room in
            room.calls[0].record(.toolFinished(id: "a3", output: """
                @@ -41,2 +41,4 @@
                +    guard limiter.allow(user.id, at: .now) else { throw HTTPError.tooManyRequests }
                """, failed: false))
            room.calls[2].record(.thinking("The bucket refills from the wall clock; a monotonic clock would survive clock changes."))
        }
        s.after(5.4) { room in
            room.calls[0].record(.toolStarted(id: "a4", name: "Write", input: "Tests/API/RateLimiterTests.swift"))
            room.calls[0].record(.toolFinished(id: "a4", output: "+func testTwentyFirstRequestGets429()", failed: false))
            room.calls[1].record(.toolStarted(id: "i3", name: "Bash", input: "swift test --filter TripsSnapshots"))
        }
        s.after(6.6) { room in
            room.calls[1].record(.toolFinished(id: "i3", output: "✘ testEmptyState: no reference image", failed: true))
            room.calls[2].logText("One note for Atlas: use a monotonic clock for the refill. Otherwise it looks good.")
            room.calls[0].record(.toolStarted(id: "a5", name: "Bash", input: "swift test"))
        }
        s.after(8.0) { room in
            room.calls[2].record(.usage(inputTokens: 12_900, outputTokens: 410, cost: nil))
            room.calls[2].state = .ready
        }
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

/// What's on screen at one moment, besides the room: the camera, the cursor, the open windows, the keys held.
struct Stage {
    enum Window { case panel, missionControl, endCard }

    /// Starts on the whole 1280×800 canvas.
    var camera = (focus: CGPoint(x: 640, y: 400), zoom: 1.0)
    var cursor = CGPoint.zero
    /// Seconds since the last click, for its ripple.
    var sinceClick: Double?
    /// Seconds each window has been open.
    var open: [Window: Double] = [:]
    var keys: String?
}

/// Builds the demo's timeline: room changes, screen changes, captions and sounds placed on one track.
@MainActor final class Script {
    static let sampleRate = 24_000.0

    private(set) var time = 0.0
    private(set) var audio: [Float] = []
    private var steps: [(at: Double, apply: (Room) -> Void)] = []
    private var captions: [(at: Double, text: String?)] = []
    /// Agent lines that appear word by word while they are spoken.
    private var reveals: [(call: Int, start: Double, end: Double, text: String)] = []
    private var moves: [(start: Double, end: Double, to: CGPoint)] = []
    private var shots: [(start: Double, end: Double, focus: CGPoint, zoom: Double)] = []
    private var clicks: [Double] = []
    private var windows: [(at: Double, window: Stage.Window, open: Bool)] = []
    private var keyPresses: [(start: Double, end: Double, keys: String)] = []
    private let voice: VoiceModels

    init(voice: VoiceModels) {
        self.voice = voice
    }

    func wait(_ seconds: Double) { time += seconds }
    func at(_ apply: @escaping (Room) -> Void) { steps.append((time, apply)) }
    /// A room change `delay` seconds from now, while the script carries on.
    func after(_ delay: Double, _ apply: @escaping (Room) -> Void) { steps.append((time + delay, apply)) }
    func caption(_ text: String?) { captions.append((time, text)) }
    func cursor(to point: CGPoint, over seconds: Double) { moves.append((time, time + seconds, point)) }
    func camera(to focus: CGPoint, zoom: Double, over seconds: Double) { shots.append((time, time + seconds, focus, zoom)) }
    func show(_ window: Stage.Window) { windows.append((time, window, true)) }
    func hide(_ window: Stage.Window) { windows.append((time, window, false)) }
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
        let samples = try await voice.speech(for: text, voice: Demo.you, language: .english)
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
        let samples = try await voice.speech(for: text, voice: Demo.agents[call].voice, language: Demo.agents[call].spokenLanguage)
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

    /// One line from an agent that isn't in focus, in its own voice, as Lair says it.
    func announce(_ call: Int, _ text: String) async throws {
        let samples = try await voice.speech(for: text, voice: Demo.agents[call].voice, language: Demo.agents[call].spokenLanguage)
        time += place(samples, at: time) + 0.3
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
            + clicks.map { String(format: "%5.1f s  click", $0) }
            + [String(format: "%5.1f s  end", time)]).joined(separator: "\n")
    }

    func caption(at time: Double) -> String? {
        captions.last { $0.at <= time }?.text
    }

    func stage(at time: Double) -> Stage {
        var stage = Stage()
        for move in moves where move.start <= time {
            let eased = Self.ease(move.start, move.end, time)
            let from = stage.cursor
            stage.cursor = CGPoint(x: from.x + (move.to.x - from.x) * eased, y: from.y + (move.to.y - from.y) * eased)
        }
        for shot in shots where shot.start <= time {
            let eased = Self.ease(shot.start, shot.end, time)
            let (from, zoom) = stage.camera
            stage.camera = (CGPoint(x: from.x + (shot.focus.x - from.x) * eased, y: from.y + (shot.focus.y - from.y) * eased),
                            zoom + (shot.zoom - zoom) * eased)
        }
        stage.sinceClick = clicks.last { $0 <= time }.map { time - $0 }
        for change in windows where change.at <= time {
            stage.open[change.window] = change.open ? time - change.at : nil
        }
        stage.keys = keyPresses.last { $0.start <= time && time < $0.end }?.keys
        return stage
    }

    /// Ease-in-out progress of a move from `start` to `end`, at `time`.
    private static func ease(_ start: Double, _ end: Double, _ time: Double) -> Double {
        let progress = end > start ? min(1, (time - start) / (end - start)) : 1
        return progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
    }

    func room(at time: Double) -> Room {
        let room = Room(config: LairConfig(agents: Demo.agents))
        room.readiness = .ready
        // Steps scheduled ahead with `after` land in time order, not in the order they were written.
        for step in steps.enumerated().sorted(by: { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) })
        where step.element.at <= time {
            step.element.apply(room)
        }
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

/// One frame of the video: the desktop with Lair's floating orb, its panel and Mission Control when open, and the
/// cursor, seen through a camera that moves in on what matters; the caption and keys sit on top, unzoomed.
private struct DemoFrame: View {
    let room: Room
    let stage: Stage
    let mission: CGImage?
    let caption: String?
    let time: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            camera(desktop)
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
                    .background(.black.opacity(0.62), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: Demo.canvas.height - 128)
            }
            if let opened = stage.open[.endCard] {
                EndCard().appearing(opened, duration: 0.6)
            }
        }
        .frame(width: Demo.canvas.width, height: Demo.canvas.height, alignment: .topLeading)
        .clipped()
        .environment(\.renderTime, time)
        .environment(\.colorScheme, .dark)
    }

    /// Scales the desktop around the camera's focus, never showing past its edges.
    private func camera(_ content: some View) -> some View {
        let (focus, zoom) = stage.camera
        let size = Demo.canvas
        let x = min(0, max(size.width - size.width * zoom, size.width / 2 - focus.x * zoom))
        let y = min(0, max(size.height - size.height * zoom, size.height / 2 - focus.y * zoom))
        return content
            .scaleEffect(zoom, anchor: .topLeading)
            .offset(x: x, y: y)
    }

    private var desktop: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
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
                    .offset(x: Demo.panelOrigin.x, y: Demo.panelOrigin.y)
                    .appearing(opened)
            }
            Cursor(sinceClick: stage.sinceClick)
                .offset(x: stage.cursor.x, y: stage.cursor.y)
        }
        .frame(width: Demo.canvas.width, height: Demo.canvas.height, alignment: .topLeading)
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
            Text("Finder").fontWeight(.semibold)
            ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
            Spacer()
            MenuBarIcon(room: room)
                .foregroundStyle(.white)
                .frame(width: 28, height: 22)
                .background(stage.open[.panel] == nil ? .clear : .white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
            // Fixed width, so the Lair icon sits exactly at Demo.menuIcon.
            HStack(spacing: 18) {
                Image(systemName: "battery.75percent")
                Image(systemName: "wifi")
                Text("Tue 10:24 AM")
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
                Text("All your coding agents, by voice, side by side.\nSpeech stays on your Mac.")
                    .font(.system(size: 22, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
        }
        .frame(width: Demo.canvas.width, height: Demo.canvas.height)
    }
}
