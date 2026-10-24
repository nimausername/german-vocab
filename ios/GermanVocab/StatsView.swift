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
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func statsList(_ stats: UserStats) -> some View {
        List {
            Section("Streak") {
                LabeledContent("Current streak") {
                    Text("\(stats.streak) days")
                        .font(.title2.bold())
                        .monospacedDigit()
                }
                .accessibilityLabel("\(stats.streak) day streak")
            }

            Section("Lexicon") {
                HStack(spacing: 16) {
                    Gauge(value: learnProgress) {
                        Text("Learned")
                    } currentValueLabel: {
                        Text("\(Int((learnProgress * 100).rounded()))%")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(AppTheme.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(stats.wordsLearned) of \(stats.wordsTotal)")
                            .font(.title2.bold())
                        Text("\(stats.matureCards) mature")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stats.wordsLearned) of \(stats.wordsTotal) words learned")
            }

            Section("Activity") {
                LabeledContent("Reviews today", value: "\(stats.reviewsToday)")
                LabeledContent("Due next 7 days", value: "\(stats.reviewsDueNext7Days)")
                LabeledContent("Daily new limit", value: "\(stats.dailyNewLimit)")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
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
