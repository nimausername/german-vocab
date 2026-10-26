import Foundation
import WatchConnectivity

/// Sends the signed-in session to the paired Apple Watch and accepts a refreshed session back.
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()

    var onActivated: (() -> Void)?
    var onRemoteTokens: ((String, String) -> Void)?

    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private var accessToken = ""
    private var refreshToken = ""
    private var planStamp = ""

    private enum Keys {
        static let planStamp = "watchPlanStamp"
    }

    private override init() {
        super.init()
    }

    func start(accessToken: String?, refreshToken: String?) {
        planStamp = defaults.string(forKey: Keys.planStamp) ?? ""
        store(accessToken: accessToken, refreshToken: refreshToken)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func push(accessToken: String?, refreshToken: String?) {
        store(accessToken: accessToken, refreshToken: refreshToken)
        if (accessToken ?? "").isEmpty {
            setPlanStamp("")
        }
        transmit()
    }

    /// Tells the watch that the phone's copy of today's queue changed.
    func updatePlanStamp(_ stamp: String) {
        guard stamp != currentPlanStamp() else { return }
        setPlanStamp(stamp)
        transmit()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onActivated?()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message["request"] as? String == "tokens" {
            replyHandler(context())
            return
        }
        deliver(message)
        replyHandler([:])
    }

    private func deliver(_ payload: [String: Any]) {
        let access = payload[WatchSyncKey.access] as? String ?? ""
        let refresh = payload[WatchSyncKey.refresh] as? String ?? ""
        DispatchQueue.main.async { [weak self] in
            self?.onRemoteTokens?(access, refresh)
        }
    }

    private func store(accessToken: String?, refreshToken: String?) {
        lock.lock()
        self.accessToken = accessToken ?? ""
        self.refreshToken = refreshToken ?? ""
        lock.unlock()
    }

    private func currentPlanStamp() -> String {
        lock.lock()
        defer { lock.unlock() }
        return planStamp
    }

    private func setPlanStamp(_ stamp: String) {
        lock.lock()
        planStamp = stamp
        lock.unlock()
        if stamp.isEmpty {
            defaults.removeObject(forKey: Keys.planStamp)
        } else {
            defaults.set(stamp, forKey: Keys.planStamp)
        }
    }

    private func transmit() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(context())
    }

    /// Sends the current reminder schedule to the watch.
    func syncReminders() {
        transmit()
    }

    /// Asks the reachable watch to show a reminder in a few seconds.
    func sendTestReminder() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(
            ["request": "test-reminder"],
            replyHandler: { _ in },
            errorHandler: { _ in }
        )
    }

    private func context() -> [String: Any] {
        lock.lock()
        let access = accessToken
        let refresh = refreshToken
        let stamp = planStamp
        lock.unlock()
        let preferences = ReminderPreferences.load()
        let reminder = ReminderContext.load()
        let minutes = preferences.reminderMinutes().map(String.init).joined(separator: ",")
        return [
            WatchSyncKey.access: access,
            WatchSyncKey.refresh: refresh,
            WatchSyncKey.planStamp: stamp,
            WatchSyncKey.remindersEnabled: preferences.enabled ? "1" : "0",
            WatchSyncKey.reminderMinutes: minutes,
            WatchSyncKey.reminderStreak: String(reminder.streak),
            WatchSyncKey.reminderStudied: reminder.studiedToday ? "1" : "0",
            WatchSyncKey.reminderWords: String(reminder.wordCount),
        ]
    }
}
