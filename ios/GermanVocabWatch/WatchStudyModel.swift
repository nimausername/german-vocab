import Foundation
import WatchConnectivity

/// Loads today's queue on the watch and records Learned or Not yet.
@MainActor
final class WatchStudyModel: NSObject, ObservableObject {
    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var queue: [StudyItem] = []
    @Published var revealed = false
    @Published var errorMessage: String?

    private let client = APIClient()
    private let defaults = UserDefaults.standard
    private var accessToken: String?
    private var refreshToken: String?
    private var startedAt = Date()
    private var didStart = false

    var current: StudyItem? { queue.first }

    func start() {
        guard !didStart else { return }
        didStart = true
        accessToken = defaults.string(forKey: WatchSyncKey.access)
        refreshToken = defaults.string(forKey: WatchSyncKey.refresh)
        isSignedIn = !(accessToken ?? "").isEmpty
        guard WCSession.isSupported() else {
            if isSignedIn { Task { await load() } }
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func load() async {
        guard isSignedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let plan = try await withAuth { token in
                try await self.client.todayPlan(token: token)
            }
            queue = plan.queue
            revealed = false
            startedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func mark(learned: Bool) async {
        guard let item = current, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let rating: Rating = learned ? .good : .again
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        do {
            _ = try await withAuth { token in
                try await self.client.submitReview(
                    token: token,
                    cardId: item.cardId,
                    rating: rating,
                    durationMs: durationMs
                )
            }
            if !queue.isEmpty {
                queue.removeFirst()
            }
            revealed = false
            startedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        queue = []
        defaults.removeObject(forKey: WatchSyncKey.access)
        defaults.removeObject(forKey: WatchSyncKey.refresh)
    }

    private func requestTokensFromPhone() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if let access = session.receivedApplicationContext[WatchSyncKey.access] as? String,
           let refresh = session.receivedApplicationContext[WatchSyncKey.refresh] as? String {
            apply(access: access, refresh: refresh)
        }
        guard session.isReachable else {
            if isSignedIn { Task { await load() } }
            return
        }
        session.sendMessage(["request": "tokens"], replyHandler: { [weak self] reply in
            let access = reply[WatchSyncKey.access] as? String ?? ""
            let refresh = reply[WatchSyncKey.refresh] as? String ?? ""
            Task { @MainActor in
                self?.apply(access: access, refresh: refresh)
                if self?.isSignedIn == true {
                    await self?.load()
                }
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                if self?.isSignedIn == true {
                    await self?.load()
                }
            }
        })
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
            requestTokensFromPhone()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let access = applicationContext[WatchSyncKey.access] as? String ?? ""
        let refresh = applicationContext[WatchSyncKey.refresh] as? String ?? ""
        Task { @MainActor in
            let unchanged = isSignedIn && access == accessToken && refresh == refreshToken
            apply(access: access, refresh: refresh)
            if isSignedIn && !unchanged {
                await load()
            }
        }
    }
}
