import Foundation

enum AppConfig {
    /// Production API (Coolify). For local API use `http://127.0.0.1:3080`.
    static let apiBaseURL = URL(string: "https://vocab-api.nimakhabbazi.de")!
}

/// Keys shared by the iPhone app and the watch when passing the signed-in session.
enum WatchSyncKey {
    static let access = "accessToken"
    static let refresh = "refreshToken"
}
