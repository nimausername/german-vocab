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
    }
}
