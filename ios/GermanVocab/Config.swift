import Foundation

enum AppConfig {
    /// Base URL of the German Vocab API.
    /// - Local API: `http://127.0.0.1:3080` (Simulator) or `http://YOUR_MAC_LAN_IP:3080` (device)
    /// - Production / Coolify: `https://your-api.example.com`
    static let apiBaseURL = URL(string: "http://127.0.0.1:3080")!
}
