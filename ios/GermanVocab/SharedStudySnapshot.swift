import Foundation
import WidgetKit

/// App Group shared with the home-screen widget.
enum AppGroupConfig {
    static let suiteName = "group.de.nimakhabbazi.germanvocab"
}

/// Compact study state the widget can show without calling the API.
struct SharedStudySnapshot: Codable, Equatable {
    var streak: Int
    var goalRemaining: Int
    var goalTotal: Int
    var planDate: String
    var updatedAt: Date

    private static let storageKey = "sharedStudySnapshot"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroupConfig.suiteName) ?? .standard
    }

    static func load() -> SharedStudySnapshot? {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(SharedStudySnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func save(from plan: TodayPlan) {
        save(
            SharedStudySnapshot(
                streak: plan.streak,
                goalRemaining: plan.dailyGoal.remaining,
                goalTotal: plan.dailyGoal.total,
                planDate: plan.planDate,
                updatedAt: Date()
            )
        )
    }

    /// Updates remaining cards mid-session without a full plan reload.
    static func updateRemaining(queueCount: Int, streak: Int? = nil) {
        guard var snapshot = load() else { return }
        let completed = max(0, snapshot.goalTotal - snapshot.goalRemaining)
        snapshot.goalRemaining = queueCount
        snapshot.goalTotal = max(snapshot.goalTotal, completed + queueCount)
        if let streak {
            snapshot.streak = streak
        }
        snapshot.updatedAt = Date()
        save(snapshot)
    }

    static func save(_ snapshot: SharedStudySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: GermanVocabWidgetKind.id)
    }

    static func clear() {
        defaults.removeObject(forKey: storageKey)
        WidgetCenter.shared.reloadTimelines(ofKind: GermanVocabWidgetKind.id)
    }
}

enum GermanVocabWidgetKind {
    static let id = "GermanVocabStudyWidget"
}
