import AVFoundation
import UIKit

/// Which way to move the phone so the current step's control comes to the middle of the picture.
enum TurnHint: Equatable {
    case left, right, up, down, centered

    /// The spoken line's catalog key: the same words the screen's arrow shows.
    var phraseKey: String {
        switch self {
        case .left: "Turn the phone left"
        case .right: "Turn the phone right"
        case .up: "Tilt the phone up"
        case .down: "Tilt the phone down"
        case .centered: "The target is straight ahead."
        }
    }

    /// The same for VoiceOver on the screen, in the interface language.
    var screenKey: String { self == .centered ? "In the middle of the picture" : phraseKey }
}

/// One moment of the sound guidance: where the beep sounds, how high, how often, and what to say.
struct SonarCue: Equatable {
    /// -1 is the left ear, 1 the right one.
    var pan: Float
    /// Higher when the control is above the middle of the picture.
    var pitch: Double
    /// Seconds to the next beep: shorter as the control comes nearer to the middle.
    var interval: Double
    var centered: Bool
    var hint: TurnHint

    /// The middle zone, as a share of half the picture. Leaving takes a wider step than coming in, so a shaking hand
    /// doesn't toggle it.
    static let enterZone = 0.2
    static let exitZone = 0.32
    static let fastest = 0.15
    static let slowest = 0.9
    static let basePitch = 660.0
    /// An off-screen control counts as this far out, past the picture's edge (1).
    static let offScreen = 1.5

    static func make(_ marker: MarkerState, in size: CGSize, wasCentered: Bool) -> SonarCue {
        var dx: Double, dy: Double
        if marker.onScreen, size.width > 0, size.height > 0 {
            dx = Double((marker.center.x - size.width / 2) / (size.width / 2))
            dy = Double((marker.center.y - size.height / 2) / (size.height / 2))
        } else {
            dx = Double(marker.direction.dx) * offScreen
            dy = Double(marker.direction.dy) * offScreen
        }
        let zone = wasCentered ? exitZone : enterZone
        let centered = marker.onScreen && abs(dx) < zone && abs(dy) < zone
        let error = min(max(abs(dx), abs(dy)), offScreen)
        let hint: TurnHint = centered ? .centered
            : abs(dx) >= abs(dy) ? (dx < 0 ? .left : .right)
            : (dy < 0 ? .up : .down)
        return SonarCue(pan: Float(max(-1, min(1, dx))),
                        pitch: basePitch * pow(2, -max(-1, min(1, dy)) * 0.5),  // screen y points down
                        interval: fastest + error / offScreen * (slowest - fastest),
                        centered: centered, hint: hint)
    }
}

/// When a hint is said out loud. Beeps lead while the control is in the picture; words come when it leaves the
/// picture and when it reaches the middle. A hint must hold for a moment, and words don't come too often.
struct HintGate {
    static let settle = 0.5
    static let settleCentered = 0.3
    static let gap = 2.5
    /// The same off-screen hint again, as a reminder.
    static let repeatAfter = 6.0

    private(set) var spoken: TurnHint?
    private var candidate: TurnHint?
    private var since: TimeInterval = 0
    private var lastSpokenAt = -Double.infinity

    mutating func reset() {
        self = HintGate()
    }

    /// The hint to say now, or nil.
    mutating func update(_ hint: TurnHint, onScreen: Bool, at now: TimeInterval) -> TurnHint? {
        if hint != candidate {
            candidate = hint
            since = now
        }
        guard now - since >= (hint == .centered ? Self.settleCentered : Self.settle) else { return nil }
        if onScreen && hint != .centered {
            // Off the middle but in the picture: the beeps say it. Coming back to the middle is said again.
            if spoken == .centered { spoken = nil }
            return nil
        }
        if hint == spoken {
            guard hint != .centered, now - lastSpokenAt >= Self.repeatAfter else { return nil }
        } else if hint != .centered && now - lastSpokenAt < Self.gap {
            return nil
        }
        spoken = hint
        lastSpokenAt = now
        return hint
    }
}

/// Sound guidance for using Kokobubu without looking at the screen: beeps that lead the camera to the control (left
/// and right in the ears, higher above, faster nearer), a tap of the phone at the middle, and short spoken hints.
/// On by itself while VoiceOver runs; Settings › Sound guidance turns it on without it. Every tone is made here, so
/// there are no sound files or licenses to follow.
@MainActor
final class SoundGuidance {
    struct Context {
        /// Settings › Sound guidance, or VoiceOver is running.
        var enabled: Bool
        /// A step is shown and waits for the user: not while listening, checking or after a passed check.
        var active: Bool
        /// Kokobubu is reading a step aloud; beeps and hints wait.
        var busy: Bool
        var speech: Bool
        var haptics: Bool
        var marker: MarkerState?
        var size: CGSize
        /// Meters to the control; nil when its place was only guessed.
        var distance: Float?
        var step: Int
        /// How to find the step's control by hand; said once the control is straight ahead.
        var touch: String? = nil
        var language: UserLanguage
    }

    var context: () -> Context? = { nil }
    private var loop: Task<Void, Never>?
    private var gate = HintGate()
    private var centered = false
    private var nextBeep: TimeInterval = 0
    private var step: Int?
    private let voice = AVSpeechSynthesizer()
    private var players: [AVAudioPlayer] = []
    private var tones: [Int: Data] = [:]
    private static let tick = 0.05

    static var voiceOverRunning: Bool { UIAccessibility.isVoiceOverRunning }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.update()
                try? await Task.sleep(for: .seconds(Self.tick))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        reset()
    }

    private func reset() {
        gate.reset()
        centered = false
        step = nil
        if voice.isSpeaking { voice.stopSpeaking(at: .immediate) }
    }

    private func update() {
        guard let context = context(), context.enabled, context.active, let marker = context.marker else {
            if step != nil || centered { reset() }
            return
        }
        if context.step != step {
            reset()
            step = context.step
        }
        let now = ProcessInfo.processInfo.systemUptime
        let cue = SonarCue.make(marker, in: context.size, wasCentered: centered)
        if cue.centered != centered {
            centered = cue.centered
            if centered && context.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
        guard !context.busy else {
            nextBeep = now + 0.3  // a short breath after the step is read
            return
        }
        if context.speech, !voice.isSpeaking, let hint = gate.update(cue.hint, onScreen: marker.onScreen, at: now) {
            say(line(for: hint, context), context)
            nextBeep = now + 1.2
            return
        }
        guard !centered, !voice.isSpeaking, now >= nextBeep else { return }
        beep(cue)
        nextBeep = now + cue.interval
    }

    /// "Where is it?": the way to the control in words, at any time, also with sound guidance off.
    func sayWhere() {
        guard let context = context(), let marker = context.marker else { return }
        let cue = SonarCue.make(marker, in: context.size, wasCentered: centered)
        say(line(for: cue.hint, context), context)
    }

    func line(for hint: TurnHint, _ context: Context) -> String {
        let way = direction(for: hint, context)
        guard hint == .centered, let touch = context.touch, !touch.isEmpty else { return way }
        return way + " " + touch
    }

    private func direction(for hint: TurnHint, _ context: Context) -> String {
        guard hint == .centered, let distance = context.distance else { return context.language.phrase(hint.phraseKey) }
        let inches = context.language.serverName == "English" && Locale.current.measurementSystem == .us
        let key = inches ? "The target is straight ahead, about {n} inches away." : "The target is straight ahead, about {n} centimeters away."
        return context.language.phrase(key).replacingOccurrences(of: "{n}", with: String(Self.amount(distance, inches: inches)))
    }

    /// A distance to say: whole inches, or centimeters to the nearest 5, never zero.
    nonisolated static func amount(_ meters: Float, inches: Bool) -> Int {
        inches ? max(1, Int((Double(meters) / 0.0254).rounded())) : max(5, Int((Double(meters) * 20).rounded()) * 5)
    }

    /// VoiceOver says it in the user's own VoiceOver voice and speed, after what it is saying now.
    private func say(_ text: String, _ context: Context) {
        if Self.voiceOverRunning {
            let announcement = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true])
            UIAccessibility.post(notification: .announcement, argument: announcement)
            return
        }
        voice.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Speaker.bestVoice(for: context.language.voice)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        voice.speak(utterance)
    }

    private func beep(_ cue: SonarCue) {
        let semitone = Int((12 * log2(cue.pitch / SonarCue.basePitch)).rounded())
        let data = tones[semitone] ?? Self.tone(SonarCue.basePitch * pow(2, Double(semitone) / 12))
        tones[semitone] = data
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.pan = cue.pan
        player.volume = 0.6
        player.play()
        players = Array((players + [player]).suffix(3))  // a beep plays to its end
    }

    /// A short sine beep with a soft start and end, as a WAV.
    static func tone(_ frequency: Double, seconds: Double = 0.07) -> Data {
        let rate = 24_000.0
        let count = Int(seconds * rate)
        let samples = (0..<count).map { i -> Int16 in
            let time = Double(i) / rate
            let envelope = min(time / 0.005, 1) * min((seconds - time) / 0.02, 1)
            return Int16(sin(2 * .pi * frequency * time) * envelope * 0.4 * 32_000)
        }
        return VoiceRecorder.wav(samples: samples, sampleRate: Int(rate))
    }
}
