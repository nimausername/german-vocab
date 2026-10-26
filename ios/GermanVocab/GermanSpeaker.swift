import AVFoundation

/// Speaks German with an installed Premium voice.
///
/// Compact and novelty voices are skipped. When no Premium German voice is
/// installed, `premiumAvailable` stays false and nothing is spoken.
@MainActor
final class GermanSpeaker: NSObject, ObservableObject {
    @Published private(set) var premiumAvailable: Bool

    private let synthesizer = AVSpeechSynthesizer()
    private let gate = SpeechFinishGate()
    private var generation = 0

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
        prepareSession()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        gate.remember(utterance, generation: spokenGeneration)
        synthesizer.speak(utterance)
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

    private func prepareSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
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
