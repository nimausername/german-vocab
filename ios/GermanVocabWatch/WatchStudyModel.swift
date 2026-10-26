import Foundation
import WatchConnectivity

/// Loads today's queue on the watch for a reading pass.
///
/// Next moves through this queue only. It does not grade the card.
///
/// The queue is kept on the watch for the rest of the local day. The phone is
/// messaged only when this watch has no session and the phone has not already
/// delivered one. A later plan from the phone is a short stamp, not the queue.
@MainActor
final class WatchStudyModel: NSObject, ObservableObject {
    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var queue: [StudyItem] = []
    @Published var revealed = false
    @Published var errorMessage: String?

    private let client = APIClient()
    private let defaults = UserDefaults.standard
    private var accessToken: String?
    private var refreshToken: String?
    private var startedAt = Date()
    private var didStart = false
    private var didRequestTokens = false
    private var cacheIsCurrent = false
    private var isFetchingPlan = false
    private var refetchAfterCurrent = false
    private var phonePlanStamp = ""
    private var lastSeenPhoneStamp = ""

    var current: StudyItem? { queue.first }

    /// True when today's saved queue is missing, or the phone has loaded a different plan.
    private var needsNetworkPlan: Bool {
        guard cacheIsCurrent else { return true }
        guard !phonePlanStamp.isEmpty else { return false }
        return phonePlanStamp != lastSeenPhoneStamp
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        accessToken = defaults.string(forKey: WatchSyncKey.access)
        refreshToken = defaults.string(forKey: WatchSyncKey.refresh)
        isSignedIn = !(accessToken ?? "").isEmpty
        restoreCachedQueue()
        guard WCSession.isSupported() else {
            if isSignedIn { Task { await load() } }
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Shows the saved queue when it is still today's plan. Pass `force` after a pull to refresh.
    func load(force: Bool = false) async {
        guard isSignedIn else { return }
        if !force && !needsNetworkPlan { return }
        if isFetchingPlan {
            refetchAfterCurrent = true
            return
        }

        isFetchingPlan = true
        let stampAtStart = phonePlanStamp
        if queue.isEmpty {
            isLoading = true
        }
        errorMessage = nil

        var fetched: TodayPlan?
        do {
            fetched = try await withAuth { token in
                try await self.client.todayPlan(token: token)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        if let fetched, isSignedIn {
            let previousCardId = queue.first?.cardId
            queue = fetched.queue
            if queue.first?.cardId != previousCardId {
                revealed = false
                startedAt = Date()
            }
            lastSeenPhoneStamp = stampAtStart
            persistCache()
            errorMessage = nil
            ReminderContext(
                streak: fetched.streak,
                studiedToday: fetched.studiedToday,
                wordCount: fetched.queue.count
            ).save()
            await StudyNotificationScheduler.reschedule()
        }

        isLoading = false
        isFetchingPlan = false

        let stampChanged = phonePlanStamp != stampAtStart
        let followUp = isSignedIn && (stampChanged || (refetchAfterCurrent && needsNetworkPlan))
        refetchAfterCurrent = false
        if followUp {
            await load(force: true)
        }
    }

    /// Moves to the next watch card. The phone schedule is left unchanged.
    func advance() {
        guard current != nil else { return }
        queue.removeFirst()
        revealed = false
        startedAt = Date()
        persistCache()
    }

    private func withAuth<T>(_ operation: (String) async throws -> T) async throws -> T {
        guard let accessToken, !accessToken.isEmpty else {
            throw APIClientError.unauthorized
        }
        do {
            return try await operation(accessToken)
        } catch APIClientError.unauthorized {
            guard let refreshToken, !refreshToken.isEmpty else {
                clearSession()
                throw APIClientError.unauthorized
            }
            let tokens = try await client.refresh(refreshToken: refreshToken)
            store(access: tokens.accessToken, refresh: tokens.refreshToken, tellPhone: true)
            return try await operation(tokens.accessToken)
        }
    }

    private func apply(access: String, refresh: String) {
        if access.isEmpty || refresh.isEmpty {
            clearSession()
            return
        }
        let newUser = WatchTokenIdentity.userId(from: access)
        let oldUser = accessToken.flatMap(WatchTokenIdentity.userId(from:))
        if let newUser, let oldUser, newUser != oldUser {
            clearCachedPlan()
        }
        store(access: access, refresh: refresh, tellPhone: false)
    }

    private func store(access: String, refresh: String, tellPhone: Bool) {
        accessToken = access
        refreshToken = refresh
        isSignedIn = true
        defaults.set(access, forKey: WatchSyncKey.access)
        defaults.set(refresh, forKey: WatchSyncKey.refresh)
        guard tellPhone, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext([
            WatchSyncKey.access: access,
            WatchSyncKey.refresh: refresh,
        ])
    }

    private func clearSession() {
        accessToken = nil
        refreshToken = nil
        isSignedIn = false
        defaults.removeObject(forKey: WatchSyncKey.access)
        defaults.removeObject(forKey: WatchSyncKey.refresh)
        clearCachedPlan()
    }

    private func clearCachedPlan() {
        queue = []
        revealed = false
        cacheIsCurrent = false
        lastSeenPhoneStamp = ""
        WatchPlanCacheStore.clear()
    }

    /// Reads the phone's last context without messaging it.
    private func syncWithPhone() async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let context = session.receivedApplicationContext
        await StudyNotificationScheduler.applySyncedPayload(context)
        let phoneHasReported = context[WatchSyncKey.access] != nil
        if phoneHasReported {
            let access = context[WatchSyncKey.access] as? String ?? ""
            let refresh = context[WatchSyncKey.refresh] as? String ?? ""
            apply(access: access, refresh: refresh)
        }
        if let stamp = context[WatchSyncKey.planStamp] as? String {
            phonePlanStamp = stamp
        }
        guard isSignedIn else {
            // Wake the iPhone only when neither side has a session yet.
            if !phoneHasReported {
                requestTokensFromPhone()
            }
            return
        }
        restoreCachedQueue()
        await load()
    }

    private func requestTokensFromPhone() {
        guard !didRequestTokens, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        didRequestTokens = true
        session.sendMessage(["request": "tokens"], replyHandler: { [weak self] reply in
            let access = reply[WatchSyncKey.access] as? String ?? ""
            let refresh = reply[WatchSyncKey.refresh] as? String ?? ""
            let stamp = reply[WatchSyncKey.planStamp] as? String
            Task { @MainActor in
                guard let self else { return }
                self.apply(access: access, refresh: refresh)
                if let stamp {
                    self.phonePlanStamp = stamp
                }
                guard self.isSignedIn else { return }
                self.restoreCachedQueue()
                await self.load()
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.didRequestTokens = false
            }
        })
    }

    private func restoreCachedQueue() {
        guard isSignedIn, !cacheIsCurrent else { return }
        guard let accessToken, let userId = WatchTokenIdentity.userId(from: accessToken) else { return }
        guard let snapshot = WatchPlanCacheStore.load(today: WatchLocalDay.today, userId: userId) else { return }
        queue = snapshot.queue
        lastSeenPhoneStamp = snapshot.lastSeenPhoneStamp
        cacheIsCurrent = true
    }

    private func persistCache() {
        guard let accessToken, let userId = WatchTokenIdentity.userId(from: accessToken) else { return }
        WatchPlanCacheStore.save(
            WatchPlanCacheStore.Snapshot(
                savedOnDay: WatchLocalDay.today,
                userId: userId,
                lastSeenPhoneStamp: lastSeenPhoneStamp,
                queue: queue
            )
        )
        cacheIsCurrent = true
    }
}

extension WatchStudyModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            await syncWithPhone()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["request"] as? String == "test-reminder" else { return }
        Task { @MainActor in
            _ = await StudyNotificationScheduler.sendTest()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["request"] as? String == "test-reminder" else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            _ = await StudyNotificationScheduler.sendTest()
        }
        replyHandler([:])
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let access = applicationContext[WatchSyncKey.access] as? String ?? ""
        let refresh = applicationContext[WatchSyncKey.refresh] as? String ?? ""
        let hasTokens = applicationContext[WatchSyncKey.access] != nil
        let stamp = applicationContext[WatchSyncKey.planStamp] as? String
        Task { @MainActor in
            await StudyNotificationScheduler.applySyncedPayload(applicationContext)
            if hasTokens {
                apply(access: access, refresh: refresh)
            }
            if let stamp {
                phonePlanStamp = stamp
            }
            guard isSignedIn else { return }
            restoreCachedQueue()
            await load()
        }
    }
}

/// Local calendar day used to decide when the saved queue expires.
private enum WatchLocalDay {
    static var today: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Reads the Keycloak subject from an access token without verifying the signature.
private enum WatchTokenIdentity {
    static func userId(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String,
              !subject.isEmpty else {
            return nil
        }
        return subject
    }
}

/// Today's queue stored in the caches directory so a later open can skip the network.
private enum WatchPlanCacheStore {
    struct Snapshot: Codable {
        var savedOnDay: String
        var userId: String
        var lastSeenPhoneStamp: String
        var queue: [StudyItem]
    }

    static func load(today: String, userId: String) -> Snapshot? {
        guard let snapshot = read(), snapshot.savedOnDay == today, snapshot.userId == userId else {
            return nil
        }
        return snapshot
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("watch-today-plan.json", isDirectory: false)
    }
}
