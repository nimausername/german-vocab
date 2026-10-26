import Foundation
import SwiftUI
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var isAuthenticated = false
    @Published var isBusy = false
    @Published var errorMessage: String?
    /// True when the visible Today plan came from disk instead of the API.
    @Published var isShowingCachedPlan = false
    @Published var pendingReviewCount = 0
    @Published var isSyncingOffline = false

    private let client = APIClient()
    private let defaults = UserDefaults.standard
    private var flushTask: Task<Void, Never>?
    /// One shared refresh so parallel 401s do not burn a rotated Keycloak refresh token.
    private var refreshTask: Task<TokenPayload, Error>?

    private enum Keys {
        static let access = "accessToken"
        static let refresh = "refreshToken"
    }

    private var cacheUserId: String {
        if let accessToken, let userId = AccessTokenIdentity.userId(from: accessToken) {
            return userId
        }
        return "local"
    }

    init() {
        accessToken = defaults.string(forKey: Keys.access)
        refreshToken = defaults.string(forKey: Keys.refresh)
        isAuthenticated = accessToken != nil
        pendingReviewCount = OfflineStore.pendingReviews(userId: cacheUserId).count
        PhoneWatchBridge.shared.onActivated = { [weak self] in
            self?.syncWatch()
        }
        PhoneWatchBridge.shared.onRemoteTokens = { [weak self] access, refresh in
            self?.applyRemoteTokens(access: access, refresh: refresh)
        }
        PhoneWatchBridge.shared.start(accessToken: accessToken, refreshToken: refreshToken)

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.flushPendingReviews()
            }
        }
    }

    func login(username: String, password: String) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let tokens = try await client.login(username: username, password: password)
            persist(tokens)
            await flushPendingReviews()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register(
        username: String,
        password: String,
        firstName: String,
        lastName: String,
        email: String?
    ) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let tokens = try await client.register(
                username: username,
                password: password,
                firstName: firstName,
                lastName: lastName,
                email: email
            )
            persist(tokens)
            await flushPendingReviews()
        } catch {
            // Account already exists from a partial earlier attempt — sign in instead.
            if case APIClientError.server(let code, let message) = error,
               code == "USERNAME_TAKEN" || code == "ACCOUNT_CREATED" {
                do {
                    let tokens = try await client.login(username: username, password: password)
                    persist(tokens)
                    await flushPendingReviews()
                    return
                } catch {
                    // Keep the real reason visible (e.g. Keycloak profile incomplete).
                    errorMessage = error.localizedDescription.isEmpty
                        ? message
                        : error.localizedDescription
                    return
                }
            }
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        clearLocalSession(syncWatch: true)
    }

    private func clearLocalSession(syncWatch: Bool) {
        let userId = cacheUserId
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        isShowingCachedPlan = false
        pendingReviewCount = 0
        refreshTask = nil
        defaults.removeObject(forKey: Keys.access)
        defaults.removeObject(forKey: Keys.refresh)
        OfflineStore.clearAll(userId: userId)
        if syncWatch {
            PhoneWatchBridge.shared.push(accessToken: nil, refreshToken: nil)
        }
    }

    func validAccessToken() async throws -> String {
        if let accessToken {
            return accessToken
        }
        throw APIClientError.unauthorized
    }

    func withAuthRetry<T>(_ operation: (String) async throws -> T) async throws -> T {
        do {
            let token = try await validAccessToken()
            return try await operation(token)
        } catch APIClientError.unauthorized {
            do {
                let tokens = try await refreshSession()
                return try await operation(tokens.accessToken)
            } catch {
                if case APIClientError.unauthorized = error {
                    clearLocalSession(syncWatch: true)
                }
                throw error
            }
        }
    }

    /// Refreshes once for the whole app. Callers that hit 401 together share this task.
    private func refreshSession() async throws -> TokenPayload {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task<TokenPayload, Error> { [weak self] in
            guard let self else { throw APIClientError.unauthorized }
            guard let refreshToken = self.refreshToken, !refreshToken.isEmpty else {
                throw APIClientError.unauthorized
            }
            do {
                let tokens = try await self.client.refresh(refreshToken: refreshToken)
                self.persist(tokens)
                return tokens
            } catch {
                throw error
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func loadTodayPlan() async throws -> TodayPlan {
        do {
            let plan = try await withAuthRetry { token in
                try await client.todayPlan(token: token)
            }
            OfflineStore.savePlan(plan, userId: cacheUserId)
            isShowingCachedPlan = false
            await flushPendingReviews()
            return plan
        } catch {
            if isNetworkFailure(error),
               let cached = OfflineStore.loadPlan(userId: cacheUserId, planDate: LocalDay.today) {
                isShowingCachedPlan = true
                return cached
            }
            throw error
        }
    }

    func submitReview(cardId: String, rating: Rating, durationMs: Int) async throws -> ReviewResult {
        let requestId = UUID().uuidString.lowercased()
        do {
            let result = try await withAuthRetry { token in
                try await client.submitReview(
                    token: token,
                    cardId: cardId,
                    rating: rating,
                    durationMs: durationMs,
                    clientRequestId: requestId
                )
            }
            OfflineStore.removeCardFromCachedPlan(
                cardId: cardId,
                userId: cacheUserId,
                planDate: LocalDay.today
            )
            return result
        } catch {
            guard isNetworkFailure(error) else { throw error }
            let pending = PendingReview(
                id: requestId,
                cardId: cardId,
                rating: rating.rawValue,
                durationMs: durationMs,
                createdAt: Date()
            )
            OfflineStore.enqueueReview(pending, userId: cacheUserId)
            OfflineStore.removeCardFromCachedPlan(
                cardId: cardId,
                userId: cacheUserId,
                planDate: LocalDay.today
            )
            pendingReviewCount = OfflineStore.pendingReviews(userId: cacheUserId).count
            return ReviewResult(
                cardId: cardId,
                due: ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400)),
                state: 0,
                reps: 0,
                streak: 0
            )
        }
    }

    /// Sends queued offline reviews when the network is available.
    func flushPendingReviews() async {
        guard isAuthenticated else { return }
        let pending = OfflineStore.pendingReviews(userId: cacheUserId)
        pendingReviewCount = pending.count
        guard !pending.isEmpty else { return }
        guard NetworkMonitor.shared.isOnline else { return }
        guard flushTask == nil else { return }

        isSyncingOffline = true
        flushTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.flushTask = nil
                self.isSyncingOffline = false
                self.pendingReviewCount = OfflineStore.pendingReviews(userId: self.cacheUserId).count
            }

            for review in pending {
                guard NetworkMonitor.shared.isOnline else { break }
                do {
                    _ = try await withAuthRetry { token in
                        try await self.client.submitReview(
                            token: token,
                            cardId: review.cardId,
                            rating: Rating(rawValue: review.rating) ?? .good,
                            durationMs: review.durationMs,
                            clientRequestId: review.id
                        )
                    }
                    OfflineStore.removeReview(id: review.id, userId: self.cacheUserId)
                } catch {
                    if self.isNetworkFailure(error) {
                        break
                    }
                    // Drop reviews the server permanently rejects so the queue cannot stick.
                    if case APIClientError.server = error {
                        OfflineStore.removeReview(id: review.id, userId: self.cacheUserId)
                    } else if case APIClientError.unauthorized = error {
                        break
                    } else {
                        OfflineStore.removeReview(id: review.id, userId: self.cacheUserId)
                    }
                }
            }
        }
        await flushTask?.value
    }

    func updateDailyNewLimit(_ limit: Int) async throws -> Int {
        let updated = try await withAuthRetry { token in
            try await client.updateDailyNewLimit(token: token, limit: limit)
        }
        return updated.dailyNewLimit
    }

    func loadStats() async throws -> UserStats {
        try await withAuthRetry { token in
            try await client.stats(token: token)
        }
    }

    func loadWords(
        page: Int,
        limit: Int = 50,
        search: String? = nil,
        cefrLevel: String? = nil,
        gender: String? = nil,
        status: WordListStatus = .all
    ) async throws -> WordListPage {
        try await withAuthRetry { token in
            try await client.words(
                token: token,
                page: page,
                limit: limit,
                search: search,
                cefrLevel: cefrLevel,
                gender: gender,
                status: status
            )
        }
    }

    func loadWord(id: String) async throws -> LexiconWord {
        try await withAuthRetry { token in
            try await client.word(token: token, id: id)
        }
    }

    func exportProgress(format: ProgressExportFormat) async throws -> ProgressExportPayload {
        try await withAuthRetry { token in
            try await client.exportProgress(token: token, format: format)
        }
    }

    private func isNetworkFailure(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }
        return false
    }

    private func persist(_ tokens: TokenPayload) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        isAuthenticated = true
        defaults.set(tokens.accessToken, forKey: Keys.access)
        defaults.set(tokens.refreshToken, forKey: Keys.refresh)
        pendingReviewCount = OfflineStore.pendingReviews(userId: cacheUserId).count
        syncWatch()
    }

    private func syncWatch() {
        PhoneWatchBridge.shared.push(accessToken: accessToken, refreshToken: refreshToken)
    }

    /// Applies a session the watch refreshed.
    ///
    /// Empty tokens are ignored. The watch used to wipe the phone session when a
    /// WatchConnectivity payload arrived without tokens (reminders, stale context).
    private func applyRemoteTokens(access: String, refresh: String) {
        guard !access.isEmpty, !refresh.isEmpty else { return }
        guard access != accessToken || refresh != refreshToken else { return }
        accessToken = access
        refreshToken = refresh
        isAuthenticated = true
        defaults.set(access, forKey: Keys.access)
        defaults.set(refresh, forKey: Keys.refresh)
        Task { await flushPendingReviews() }
    }
}
