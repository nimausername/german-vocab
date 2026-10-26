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
                    LoadingView(message: "Loading stats")
                } else if let stats {
                    statsList(stats)
                } else if let errorMessage {
                    LoadFailureView(title: "Couldn’t load stats", message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    LoadingView(message: "Preparing stats")
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.rotate, isActive: isLoading)
                    }
                    .accessibilityLabel("Refresh stats")
                    .disabled(isLoading)
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func statsList(_ stats: UserStats) -> some View {
        List {
            Section("Streak") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, value: stats.streak)
                        .accessibilityHidden(true)

                    Text("\(stats.streak)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(stats.streak == 1 ? "day" : "days")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stats.streak) day streak")
            }

            Section("Lexicon") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(stats.wordsLearned) of \(stats.wordsTotal)")
                            .font(.title2.bold())
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Spacer()
                        Text("\(Int((learnProgress * 100).rounded()))%")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }

                    Gauge(value: learnProgress) {
                        Text("Learned")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(AppTheme.accent)
                    .animation(AppMotion.reveal, value: learnProgress)

                    Text("\(stats.matureCards) mature")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stats.wordsLearned) of \(stats.wordsTotal) words learned, \(stats.matureCards) mature")
            }

            Section("Activity") {
                MetricRow(title: "Reviews today", value: "\(stats.reviewsToday)", systemImage: "checkmark.circle")
                MetricRow(title: "Due next 7 days", value: "\(stats.reviewsDueNext7Days)", systemImage: "calendar")
                MetricRow(title: "Daily new limit", value: "\(stats.dailyNewLimit)", systemImage: "sparkles")
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
