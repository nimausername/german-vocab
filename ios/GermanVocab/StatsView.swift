import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var stats: UserStats?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var learnProgress: Double {
        guard let stats, stats.wordsTotal > 0 else { return 0 }
        return Double(stats.wordsLearned) / Double(stats.wordsTotal)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && stats == nil {
                    ProgressView("Loading stats")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let stats {
                    statsList(stats)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn’t load stats",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(AppTheme.wash)
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .task { await load() }
            .refreshable { await load() }
            .tint(AppTheme.accent)
        }
    }

    private func statsList(_ stats: UserStats) -> some View {
        List {
            Section("Streak") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(stats.streak)")
                        .font(AppTheme.display(52, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .contentTransition(.numericText())
                    Text("days")
                        .font(AppTheme.headline())
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stats.streak) day streak")
            }

            Section("Lexicon") {
                HStack(spacing: 20) {
                    LearningRing(progress: learnProgress)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(stats.wordsLearned) of \(stats.wordsTotal)")
                            .font(AppTheme.display(24, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("\(stats.matureCards) mature · \(Int((learnProgress * 100).rounded()))% learned")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section("Activity") {
                LabeledContent("Reviews today", value: "\(stats.reviewsToday)")
                LabeledContent("Due next 7 days", value: "\(stats.reviewsDueNext7Days)")
                LabeledContent("Daily new limit", value: "\(stats.dailyNewLimit)")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await session.loadStats()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
