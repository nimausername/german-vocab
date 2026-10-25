import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var isAuthenticated = false
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let client = APIClient()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let access = "accessToken"
        static let refresh = "refreshToken"
    }

    init() {
        accessToken = defaults.string(forKey: Keys.access)
        refreshToken = defaults.string(forKey: Keys.refresh)
        isAuthenticated = accessToken != nil
        PhoneWatchBridge.shared.onActivated = { [weak self] in
            self?.syncWatch()
        }
        PhoneWatchBridge.shared.onRemoteTokens = { [weak self] access, refresh in
            self?.applyRemoteTokens(access: access, refresh: refresh)
        }
        PhoneWatchBridge.shared.start(accessToken: accessToken, refreshToken: refreshToken)
    }

    func login(username: String, password: String) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let tokens = try await client.login(username: username, password: password)
            persist(tokens)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        defaults.removeObject(forKey: Keys.access)
        defaults.removeObject(forKey: Keys.refresh)
        syncWatch()
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
            guard let refreshToken else { throw APIClientError.unauthorized }
            let tokens = try await client.refresh(refreshToken: refreshToken)
            persist(tokens)
            guard let accessToken else { throw APIClientError.unauthorized }
            return try await operation(accessToken)
        }
    }

    func loadTodayPlan() async throws -> TodayPlan {
        try await withAuthRetry { token in
            try await client.todayPlan(token: token)
        }
    }

    func submitReview(cardId: String, rating: Rating, durationMs: Int) async throws -> ReviewResult {
        try await withAuthRetry { token in
            try await client.submitReview(
                token: token,
                cardId: cardId,
                rating: rating,
                durationMs: durationMs
            )
        }
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

    private func persist(_ tokens: TokenPayload) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        isAuthenticated = true
        defaults.set(tokens.accessToken, forKey: Keys.access)
        defaults.set(tokens.refreshToken, forKey: Keys.refresh)
        syncWatch()
    }

    private func syncWatch() {
        PhoneWatchBridge.shared.push(accessToken: accessToken, refreshToken: refreshToken)
    }

    /// Applies a session the watch refreshed, without sending it straight back.
    private func applyRemoteTokens(access: String, refresh: String) {
        if access.isEmpty || refresh.isEmpty {
            guard isAuthenticated else { return }
            accessToken = nil
            refreshToken = nil
            isAuthenticated = false
            defaults.removeObject(forKey: Keys.access)
            defaults.removeObject(forKey: Keys.refresh)
            PhoneWatchBridge.shared.push(accessToken: nil, refreshToken: nil)
            return
        }
        guard access != accessToken || refresh != refreshToken else { return }
        accessToken = access
        refreshToken = refresh
        isAuthenticated = true
        defaults.set(access, forKey: Keys.access)
        defaults.set(refresh, forKey: Keys.refresh)
        PhoneWatchBridge.shared.push(accessToken: access, refreshToken: refresh)
    }
}
