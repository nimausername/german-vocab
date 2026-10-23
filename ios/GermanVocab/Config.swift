import Foundation

enum AppConfig {
    /// Production API (Coolify). For local API use `http://127.0.0.1:3080`.
    static let apiBaseURL = URL(string: "https://vocab-api.nimakhabbazi.de")!
}
