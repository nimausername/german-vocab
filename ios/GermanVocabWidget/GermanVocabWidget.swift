import SwiftUI
import WidgetKit

private enum WidgetKind {
    static let id = "GermanVocabStudyWidget"
}

private enum AppGroup {
    static let suiteName = "group.de.nimakhabbazi.germanvocab"
    static let snapshotKey = "sharedStudySnapshot"
}

private struct Snapshot: Codable {
    var streak: Int
    var goalRemaining: Int
    var goalTotal: Int
    var planDate: String
    var updatedAt: Date
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: Snapshot(streak: 3, goalRemaining: 8, goalTotal: 12, planDate: "", updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), snapshot: loadSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadSnapshot() -> Snapshot? {
        guard let defaults = UserDefaults(suiteName: AppGroup.suiteName),
              let data = defaults.data(forKey: AppGroup.snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

private struct GermanVocabWidgetEntryView: View {
    var entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("German Vocab")
                .font(.headline)

            if let snapshot = entry.snapshot {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(snapshot.streak)")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text(snapshot.streak == 1 ? "day" : "days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(goalLine(snapshot))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open the app to sync today’s goal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func goalLine(_ snapshot: Snapshot) -> String {
        if snapshot.goalTotal == 0 || snapshot.goalRemaining == 0 {
            return "Today’s goal is done."
        }
        if snapshot.goalRemaining == 1 {
            return "1 card left today."
        }
        return "\(snapshot.goalRemaining) cards left today."
    }
}

@main
struct GermanVocabWidgets: WidgetBundle {
    var body: some Widget {
        GermanVocabStudyWidget()
    }
}

struct GermanVocabStudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.id, provider: Provider()) { entry in
            GermanVocabWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today’s study")
        .description("Streak and cards left for today’s goal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
