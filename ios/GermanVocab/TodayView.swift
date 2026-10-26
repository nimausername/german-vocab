import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var session: SessionStore
    @Namespace private var studyTransition
    @State private var plan: TodayPlan?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showStudy = false
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && plan == nil {
                    LoadingView(message: "Building today’s plan")
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
                    LoadingView(message: "Preparing Today")
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
            .task {
                await load()
                await session.flushPendingReviews()
            }
            .refreshable { await load() }
            .onChange(of: network.isOnline) { _, online in
                if online {
                    Task {
                        await session.flushPendingReviews()
                        await load()
                    }
                }
            }
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
            if session.isShowingCachedPlan || !network.isOnline || session.pendingReviewCount > 0 {
                Section {
                    offlineStatusRow
                }
            }

            Section {
                dailyGoalBlock(plan.dailyGoal)
            }

            if let pacingNote = plan.pacingNote {
                Section {
                    Label(pacingNote, systemImage: "gauge.with.dots.needle.67percent")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, value: plan.streak)
                        .accessibilityHidden(true)

                    Text("\(plan.streak)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(plan.streak == 1 ? "day streak" : "day streak")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text(formattedDate(plan.planDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(streakLabel(plan))
            } header: {
                Text("Streak")
            }

            Section("Queue") {
                MetricRow(title: "Reviews due", value: "\(plan.reviewDue)", systemImage: "arrow.clockwise")
                MetricRow(title: "New today", value: "\(plan.newRemaining)", systemImage: "sparkles")
                if plan.settingsNewLimit != plan.newLimit {
                    MetricRow(
                        title: "New limit",
                        value: "\(plan.newLimit) of \(plan.settingsNewLimit)",
                        systemImage: "gauge"
                    )
                }
                MetricRow(
                    title: "About",
                    value: plan.queue.isEmpty ? "—" : "\(estimatedMinutes(plan.queue.count)) min",
                    systemImage: "clock"
                )
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .animation(AppMotion.reveal, value: plan.dailyGoal)
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
                    .accessibilityHint("\(plan.queue.count) cards left for today’s goal")
                }
            }
        }
    }

    private func dailyGoalBlock(_ goal: DailyGoal) -> some View {
        let progress = goal.total > 0 ? Double(goal.completed) / Double(goal.total) : 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(goalTitle(goal))
                    .font(.title2.bold())
                Spacer()
                Text("\(goal.completed)/\(max(goal.total, goal.completed))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.accent)
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: max(0, geometry.size.width * progress))
                }
            }
            .frame(height: 8)
            .animation(AppMotion.reveal, value: progress)

            Text(goalSubtitle(goal))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(goalTitle(goal)). \(goal.completed) of \(goal.total) cards. \(goalSubtitle(goal))")
    }

    private func goalTitle(_ goal: DailyGoal) -> String {
        if goal.total == 0 {
            return "Nothing due"
        }
        return goal.met ? "Goal complete" : "Today’s goal"
    }

    private func goalSubtitle(_ goal: DailyGoal) -> String {
        if goal.total == 0 {
            return "Come back tomorrow for the next set."
        }
        if goal.met {
            return "All due cards are done for today."
        }
        if goal.remaining == 1 {
            return "1 card left to finish today’s reviews and new words."
        }
        return "\(goal.remaining) cards left to finish today’s reviews and new words."
    }

    private var offlineStatusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !network.isOnline || session.isShowingCachedPlan {
                Label(
                    session.isShowingCachedPlan
                        ? "Offline — using today’s saved plan"
                        : "You’re offline",
                    systemImage: "wifi.slash"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            if session.pendingReviewCount > 0 {
                Label(
                    session.isSyncingOffline
                        ? "Syncing \(session.pendingReviewCount) saved reviews"
                        : "\(session.pendingReviewCount) reviews waiting to sync",
                    systemImage: session.isSyncingOffline ? "arrow.triangle.2.circlepath" : "tray.and.arrow.up"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func streakLabel(_ plan: TodayPlan) -> String {
        "\(formattedDate(plan.planDate)). \(plan.streak) day streak."
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
