import Foundation

enum AppConfig {
    /// Production API (Coolify). For local API use `http://127.0.0.1:3080`.
    static let apiBaseURL = URL(string: "https://vocab-api.nimakhabbazi.de")!
}

/// Keys shared by the iPhone app and the watch when passing the signed-in session.
enum WatchSyncKey {
    static let access = "accessToken"
    static let refresh = "refreshToken"
    /// Identity of the plan the phone last loaded. Empty means the phone has no snapshot.
    static let planStamp = "planStamp"
}

/// Compact identity for a daily queue, shared so the phone and watch compare the same value.
enum WatchPlanStamp {
    /**
     Builds a stable stamp from the plan date and card ids.

     The watch downloads today's queue only when this value changes, or when its
     own copy is missing or from another day.
     */
    static func make(planDate: String, queue: [StudyItem]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for id in queue.map(\.cardId) {
            for byte in id.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            hash ^= 0xFF
            hash &*= 1_099_511_628_211
        }
        return "\(planDate)|\(queue.count)|\(hash)"
    }
}
