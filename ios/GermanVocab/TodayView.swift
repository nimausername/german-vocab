import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var plan: TodayPlan?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showStudy = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && plan == nil {
                    ProgressView("Building today’s plan")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let plan {
                    planList(plan)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Couldn’t load plan",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(AppTheme.wash)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh plan")
                    .disabled(isLoading)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .navigationDestination(isPresented: $showStudy) {
                if let plan {
                    StudyView(initialQueue: plan.queue)
                }
            }
            .tint(AppTheme.accent)
        }
    }

    @ViewBuilder
    private func planList(_ plan: TodayPlan) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(formattedDate(plan.planDate))
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.muted)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(plan.streak)")
                            .font(AppTheme.display(52, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .contentTransition(.numericText())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("day streak")
                                .font(AppTheme.headline())
                                .foregroundStyle(AppTheme.inkSoft)
                            Text(plan.queue.isEmpty ? "You’re clear for today." : "Keep the chain alive.")
                                .font(AppTheme.caption())
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(plan.streak) day streak")
            }

            Section("Queue") {
                HStack(spacing: 0) {
                    metric("Reviews", value: plan.reviewDue)
                    metric("New left", value: plan.newRemaining)
                    metric("Queue", value: plan.queue.count)
                }
                .padding(.vertical, 4)
            }

            Section {
                if plan.queue.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session complete")
                            .font(AppTheme.headline())
                        Text("Come back tomorrow for the next set.")
                            .font(AppTheme.body())
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ready when you are")
                            .font(AppTheme.headline())
                        Text("\(plan.queue.count) cards · about \(estimatedMinutes(plan.queue.count)) min")
                            .font(AppTheme.body())
                            .foregroundStyle(AppTheme.muted)

                        Button {
                            showStudy = true
                        } label: {
                            Text("Start session")
                                .font(AppTheme.headline())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.ink)
                        .accessibilityLabel("Start session")
                    }
                    .padding(.vertical, 4)
                }
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

    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(AppTheme.micro())
                .tracking(0.6)
                .foregroundStyle(AppTheme.muted)
            Text("\(value)")
                .font(AppTheme.display(32, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            plan = try await session.loadTodayPlan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDate(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    private func estimatedMinutes(_ count: Int) -> Int {
        max(1, Int((Double(count) * 0.35).rounded()))
    }
}
