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
        }
    }

    @ViewBuilder
    private func planList(_ plan: TodayPlan) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formattedDate(plan.planDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(plan.streak) day streak")
                        .font(.largeTitle.bold())
                        .contentTransition(.numericText())
                    Text(plan.queue.isEmpty ? "You’re clear for today." : "Keep the chain alive.")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(plan.streak) day streak")
            }

            Section("Queue") {
                LabeledContent("Reviews", value: "\(plan.reviewDue)")
                LabeledContent("New left", value: "\(plan.newRemaining)")
                LabeledContent("In this session", value: "\(plan.queue.count)")
            }

            Section("Session") {
                if plan.queue.isEmpty {
                    Text("Come back tomorrow for the next set.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Cards", value: "\(plan.queue.count)")
                    LabeledContent("About", value: "\(estimatedMinutes(plan.queue.count)) min")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !plan.queue.isEmpty {
                Button {
                    showStudy = true
                } label: {
                    Text("Start session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 420)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
                .accessibilityLabel("Start session")
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            plan = try await session.loadTodayPlan()
            if let plan, plan.queue.count > 0 {
                await StudyNotificationScheduler.scheduleDailyReminder(wordCount: plan.queue.count)
            }
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

        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func estimatedMinutes(_ count: Int) -> Int {
        max(1, Int((Double(count) * 0.35).rounded()))
    }
}
