import Foundation

enum APIClientError: LocalizedError {
    case invalidResponse
    case server(code: String, message: String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .server(_, let message):
            return message
        case .unauthorized:
            return "Please sign in again."
        }
    }

    var code: String? {
        switch self {
        case .server(let code, _):
            return code
        case .unauthorized:
            return "UNAUTHORIZED"
        case .invalidResponse:
            return nil
        }
    }
}

final class APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL = AppConfig.apiBaseURL) {
        self.baseURL = baseURL
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
    }

    func login(username: String, password: String) async throws -> TokenPayload {
        try await post(
            path: "/v1/auth/login",
            body: ["username": username, "password": password],
            token: nil
        )
    }

    func register(
        username: String,
        password: String,
        firstName: String,
        lastName: String,
        email: String?
    ) async throws -> TokenPayload {
        var body: [String: Any] = [
            "username": username,
            "password": password,
            "firstName": firstName,
            "lastName": lastName,
        ]
        if let email, !email.isEmpty {
            body["email"] = email
        }
        return try await post(
            path: "/v1/auth/register",
            body: body,
            token: nil
        )
    }

    func refresh(refreshToken: String) async throws -> TokenPayload {
        try await post(
            path: "/v1/auth/refresh",
            body: ["refreshToken": refreshToken],
            token: nil
        )
    }

    func todayPlan(token: String) async throws -> TodayPlan {
        try await get(path: "/v1/plans/today", token: token)
    }

    func updateDailyNewLimit(token: String, limit: Int) async throws -> UserSettings {
        try await patch(
            path: "/v1/settings",
            body: ["dailyNewLimit": limit],
            token: token
        )
    }

    func settings(token: String) async throws -> UserSettings {
        try await get(path: "/v1/settings", token: token)
    }

    func updateProfileName(token: String, firstName: String, lastName: String) async throws -> UserSettings {
        try await patch(
            path: "/v1/settings",
            body: ["firstName": firstName, "lastName": lastName],
            token: token
        )
    }

    func updateStudyFilters(token: String, filters: StudyFilters) async throws -> UserSettings {
        try await patch(
            path: "/v1/settings",
            body: [
                "studyFilters": [
                    "cefrLevels": filters.cefrLevels,
                    "nounsOnly": filters.nounsOnly,
                    "tags": filters.tags,
                ] as [String: Any],
            ],
            token: token
        )
    }

    func mistakeQueue(token: String) async throws -> MistakeQueue {
        try await get(path: "/v1/plans/mistakes", token: token)
    }

    func submitReview(
        token: String,
        cardId: String,
        rating: Rating,
        durationMs: Int,
        clientRequestId: String? = nil
    ) async throws -> ReviewResult {
        var body: [String: Any] = [
            "cardId": cardId,
            "rating": rating.rawValue,
            "durationMs": durationMs,
        ]
        if let clientRequestId {
            body["clientRequestId"] = clientRequestId
        }
        return try await post(
            path: "/v1/reviews",
            body: body,
            token: token
        )
    }

    func stats(token: String) async throws -> UserStats {
        try await get(path: "/v1/stats", token: token)
    }

    func words(
        token: String,
        page: Int,
        limit: Int,
        search: String?,
        cefrLevel: String?,
        gender: String?,
        status: WordListStatus
    ) async throws -> WordListPage {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "status", value: status.rawValue),
        ]
        if let search, !search.isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        if let cefrLevel, !cefrLevel.isEmpty {
            query.append(URLQueryItem(name: "cefrLevel", value: cefrLevel))
        }
        if let gender, !gender.isEmpty {
            query.append(URLQueryItem(name: "gender", value: gender))
        }
        return try await get(path: "/v1/words", query: query, token: token)
    }

    func word(token: String, id: String) async throws -> LexiconWord {
        try await get(path: "/v1/words/\(id)", token: token)
    }

    func exportProgress(token: String, format: ProgressExportFormat) async throws -> ProgressExportPayload {
        try await get(
            path: "/v1/exports/progress",
            query: [URLQueryItem(name: "format", value: format.rawValue)],
            token: token
        )
    }

    private func makeURL(_ path: String, query: [URLQueryItem] = []) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(
            url: baseURL.appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url!
    }

    private func get<T: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        token: String?
    ) async throws -> T {
        var request = URLRequest(url: makeURL(path, query: query))
        request.httpMethod = "GET"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request)
    }

    private func post<T: Decodable>(
        path: String,
        body: [String: Any],
        token: String?
    ) async throws -> T {
        var request = URLRequest(url: makeURL(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func patch<T: Decodable>(
        path: String,
        body: [String: Any],
        token: String?
    ) async throws -> T {
        var request = URLRequest(url: makeURL(path))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if let errorBody = try? decoder.decode(APIErrorBody.self, from: data),
           !(200 ... 299).contains(http.statusCode) {
            let code = errorBody.error.code
            // Only treat real session failures as unauthorized so login/register
            // can show Keycloak messages instead of “Please sign in again.”
            if http.statusCode == 401, code == "UNAUTHORIZED" || code == "REFRESH_FAILED" {
                throw APIClientError.unauthorized
            }
            throw APIClientError.server(code: code, message: errorBody.error.message)
        }

        if http.statusCode == 401 {
            throw APIClientError.unauthorized
        }

        if !(200 ... 299).contains(http.statusCode) {
            throw APIClientError.server(
                code: "HTTP_\(http.statusCode)",
                message: "Request failed (\(http.statusCode))"
            )
        }

        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        return envelope.data
    }
}
