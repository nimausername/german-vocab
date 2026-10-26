import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var session: SessionStore
    @Namespace private var studyTransition
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
                    LoadFailureView(
                        title: "Couldn’t load plan",
                        message: errorMessage
                    ) {
                        Task { await load() }
                    }
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
                            .symbolEffect(.rotate, isActive: isLoading)
                    }
                    .accessibilityLabel("Refresh plan")
                    .disabled(isLoading)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: showStudy) { _, isShowing in
                if !isShowing {
                    Task { await load() }
                }
            }
            .navigationDestination(isPresented: $showStudy) {
                if let plan {
                    StudyView(initialQueue: plan.queue)
                        .navigationTransition(.zoom(sourceID: "start-session", in: studyTransition))
                }
            }
        }
    }

    @ViewBuilder
    private func planList(_ plan: TodayPlan) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(formattedDate(plan.planDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce, value: plan.streak)
                            .accessibilityHidden(true)

                        Text("\(plan.streak)")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        Text("day streak")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Text(plan.queue.isEmpty ? "You’re clear for today." : "Keep the chain alive.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(streakLabel(plan))
            }

            Section("Queue") {
                MetricRow(title: "Reviews", value: "\(plan.reviewDue)", systemImage: "arrow.clockwise")
                MetricRow(title: "New left", value: "\(plan.newRemaining)", systemImage: "sparkles")
                MetricRow(title: "In this session", value: "\(plan.queue.count)", systemImage: "rectangle.stack")
            }

            Section("Session") {
                if plan.queue.isEmpty {
                    Label("Come back tomorrow for the next set.", systemImage: "sun.horizon")
                        .foregroundStyle(.secondary)
                } else {
                    MetricRow(title: "Cards", value: "\(plan.queue.count)", systemImage: "square.stack")
                    MetricRow(
                        title: "About",
                        value: "\(estimatedMinutes(plan.queue.count)) min",
                        systemImage: "clock"
                    )
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .animation(AppMotion.reveal, value: plan.streak)
        .animation(AppMotion.reveal, value: plan.queue.count)
        .safeAreaBar(edge: .bottom) {
            if !plan.queue.isEmpty {
                BottomActionBar {
                    Button {
                        showStudy = true
                    } label: {
                        Label("Start Session", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .prominentGlassCapsule()
                    .actionColumn()
                    .matchedTransitionSource(id: "start-session", in: studyTransition)
                    .accessibilityLabel("Start session")
                    .accessibilityHint("\(plan.queue.count) cards, about \(estimatedMinutes(plan.queue.count)) minutes")
                }
            }
        }
    }

    private func streakLabel(_ plan: TodayPlan) -> String {
        let status = plan.queue.isEmpty ? "You’re clear for today." : "Keep the chain alive."
        return "\(formattedDate(plan.planDate)). \(plan.streak) day streak. \(status)"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let planTask = session.loadTodayPlan()
            async let statsTask = session.loadStats()
            let loadedPlan = try await planTask
            let stats = try? await statsTask
            plan = loadedPlan
            PhoneWatchBridge.shared.updatePlanStamp(
                WatchPlanStamp.make(planDate: loadedPlan.planDate, queue: loadedPlan.queue)
            )
            let studied = loadedPlan.studiedToday || (stats?.reviewsToday ?? 0) > 0
            ReminderContext(
                streak: loadedPlan.streak,
                studiedToday: studied,
                wordCount: loadedPlan.queue.count
            ).save()
            await StudyNotificationScheduler.reschedule()
            PhoneWatchBridge.shared.syncReminders()
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
