import AVFoundation

/// Speaks German with an installed Premium voice.
///
/// Compact and novelty voices are skipped. When no Premium German voice is
/// installed, `premiumAvailable` stays false and nothing is spoken.
///
/// `AVAudioSession` activate and deactivate run on a background queue so they
/// do not stall the main thread (Xcode's hang-risk warning).
@MainActor
final class GermanSpeaker: NSObject, ObservableObject {
    @Published private(set) var premiumAvailable: Bool

    private let synthesizer = AVSpeechSynthesizer()
    private let gate = SpeechFinishGate()
    private var generation = 0

    /// Serial queue for session activate/deactivate. Those calls can block.
    private static let sessionQueue = DispatchQueue(
        label: "de.nimakhabbazi.germanvocab.audio-session",
        qos: .userInitiated
    )

    override init() {
        premiumAvailable = GermanSpeaker.premiumVoice() != nil
        super.init()
        synthesizer.delegate = gate
        gate.onFinish = { [weak self] finished in
            guard let self, finished == self.generation else { return }
            self.deactivateSession()
        }
    }

    /// Checks again in case a voice was downloaded after launch.
    func refresh() {
        premiumAvailable = GermanSpeaker.premiumVoice() != nil
    }

    /// Speaks `text` when a Premium German voice is installed.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let voice = GermanSpeaker.premiumVoice() else {
            premiumAvailable = false
            return
        }
        premiumAvailable = true
        generation += 1
        let spokenGeneration = generation

        Self.sessionQueue.async { [weak self] in
            AudioSessionControl.activate()
            Task { @MainActor in
                guard let self, self.generation == spokenGeneration else { return }
                self.synthesizer.stopSpeaking(at: .immediate)
                let utterance = AVSpeechUtterance(string: trimmed)
                utterance.voice = voice
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                self.gate.remember(utterance, generation: spokenGeneration)
                self.synthesizer.speak(utterance)
            }
        }
    }

    /// Stops playback and lets other audio return to full volume.
    func stop() {
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
    }

    /// Premium `de-DE` first, then any other Premium German voice.
    static func premiumVoice() -> AVSpeechSynthesisVoice? {
        let premium = AVSpeechSynthesisVoice.speechVoices().filter { $0.quality == .premium }
        return premium.first { $0.language == "de-DE" }
            ?? premium.first { $0.language.hasPrefix("de-") }
    }

    private func deactivateSession() {
        Self.sessionQueue.async {
            AudioSessionControl.deactivate()
        }
    }
}

/// Session activate/deactivate stay off the main actor so the queue can call them.
private enum AudioSessionControl {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }
}

/// Forwards the end of an utterance. A cancelled utterance does not finish.
private final class SpeechFinishGate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (@MainActor (Int) -> Void)?
    private let lock = NSLock()
    private var generations: [ObjectIdentifier: Int] = [:]

    func remember(_ utterance: AVSpeechUtterance, generation: Int) {
        lock.lock()
        generations[ObjectIdentifier(utterance)] = generation
        lock.unlock()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        lock.lock()
        let finished = generations.removeValue(forKey: ObjectIdentifier(utterance))
        lock.unlock()
        guard let finished else { return }
        let finish = onFinish
        Task { @MainActor in
            finish?(finished)
        }
    }
}
