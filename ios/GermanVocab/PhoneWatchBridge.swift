import Foundation
import WatchConnectivity

/// Sends the signed-in session to the paired Apple Watch and accepts a refreshed session back.
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()

    var onActivated: (() -> Void)?
    var onRemoteTokens: ((String, String) -> Void)?

    private let lock = NSLock()
    private var accessToken = ""
    private var refreshToken = ""

    private override init() {
        super.init()
    }

    func start(accessToken: String?, refreshToken: String?) {
        store(accessToken: accessToken, refreshToken: refreshToken)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func push(accessToken: String?, refreshToken: String?) {
        store(accessToken: accessToken, refreshToken: refreshToken)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(context())
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

    private func context() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return [
            WatchSyncKey.access: accessToken,
            WatchSyncKey.refresh: refreshToken,
        ]
    }
}
