import Foundation

/// A review that finished on device while the API was unreachable.
struct PendingReview: Codable, Identifiable, Equatable {
    let id: String
    let cardId: String
    let rating: Int
    let durationMs: Int
    let createdAt: Date
}

/// Disk cache for today's plan and reviews waiting to sync.
enum OfflineStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("OfflineCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func planURL(userId: String) -> URL {
        rootURL.appendingPathComponent("plan-\(userId).json")
    }

    private static func pendingURL(userId: String) -> URL {
        rootURL.appendingPathComponent("pending-\(userId).json")
    }

    static func savePlan(_ plan: TodayPlan, userId: String) {
        guard let data = try? encoder.encode(plan) else { return }
        try? data.write(to: planURL(userId: userId), options: .atomic)
    }

    /// Returns the cached plan when it is still for `planDate`.
    static func loadPlan(userId: String, planDate: String) -> TodayPlan? {
        guard let data = try? Data(contentsOf: planURL(userId: userId)),
              let plan = try? decoder.decode(TodayPlan.self, from: data),
              plan.planDate == planDate else {
            return nil
        }
        return plan
    }

    static func clearPlan(userId: String) {
        try? FileManager.default.removeItem(at: planURL(userId: userId))
    }

    static func pendingReviews(userId: String) -> [PendingReview] {
        guard let data = try? Data(contentsOf: pendingURL(userId: userId)),
              let items = try? decoder.decode([PendingReview].self, from: data) else {
            return []
        }
        return items
    }

    static func enqueueReview(_ review: PendingReview, userId: String) {
        var items = pendingReviews(userId: userId)
        if items.contains(where: { $0.id == review.id }) {
            return
        }
        items.append(review)
        savePending(items, userId: userId)
    }

    static func removeReview(id: String, userId: String) {
        var items = pendingReviews(userId: userId)
        items.removeAll { $0.id == id }
        savePending(items, userId: userId)
    }

    /// Drops a finished card from the cached plan so a later offline open stays in sync.
    static func removeCardFromCachedPlan(cardId: String, userId: String, planDate: String) {
        guard var plan = loadPlan(userId: userId, planDate: planDate) else { return }
        let remaining = plan.queue.filter { $0.cardId != cardId }
        guard remaining.count != plan.queue.count else { return }
        let completed = plan.dailyGoal.completed + (plan.queue.count - remaining.count)
        plan = TodayPlan(
            planDate: plan.planDate,
            newLimit: plan.newLimit,
            settingsNewLimit: plan.settingsNewLimit,
            reviewDue: plan.reviewDue,
            newRemaining: plan.newRemaining,
            queue: remaining,
            streak: plan.streak,
            studiedToday: true,
            dailyGoal: DailyGoal(
                completed: completed,
                remaining: remaining.count,
                total: completed + remaining.count,
                met: remaining.isEmpty
            ),
            pacingNote: plan.pacingNote,
            filterNote: plan.filterNote
        )
        savePlan(plan, userId: userId)
    }

    static func clearAll(userId: String) {
        clearPlan(userId: userId)
        try? FileManager.default.removeItem(at: pendingURL(userId: userId))
    }

    private static func savePending(_ items: [PendingReview], userId: String) {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: pendingURL(userId: userId), options: .atomic)
    }
}

/// Reads the Keycloak subject from an access token without verifying the signature.
enum AccessTokenIdentity {
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

enum OfflineError: LocalizedError {
    case noCachedPlan

    var errorDescription: String? {
        switch self {
        case .noCachedPlan:
            return "You’re offline and today’s plan is not on this device yet."
        }
    }
}

enum LocalDay {
    static var today: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
