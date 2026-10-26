import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var dailyNewLimit = 20
    @State private var savedLimit = 20
    @State private var limitReady = false
    @State private var isSavingLimit = false
    @State private var limitError: String?

    @State private var preferences = ReminderPreferences.load()
    @State private var notificationsDenied = false
    @State private var reminderStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $dailyNewLimit, in: 1...50) {
                        LabeledContent {
                            Text("\(dailyNewLimit)")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .font(.body.weight(.semibold))
                        } label: {
                            Label("New words a day", systemImage: "sparkles")
                        }
                    }
                    .disabled(isSavingLimit || !limitReady)
                    .accessibilityHint("Changes how many new words join each day's plan")

                    if isSavingLimit {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Saving")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let limitError {
                        Text(limitError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Daily Plan")
                } footer: {
                    Text("Due reviews are always included. This limit only adds new words. It applies the next time Today loads.")
                }

                Section {
                    Toggle(isOn: $preferences.enabled) {
                        Label("Reminders", systemImage: "bell")
                    }
                    .accessibilityHint("Sends study reminders on this iPhone or iPad")

                    if preferences.enabled {
                        Stepper(value: $preferences.timesPerDay, in: 1...4) {
                            LabeledContent {
                                Text("\(preferences.timesPerDay)")
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .font(.body.weight(.semibold))
                            } label: {
                                Label("Times a day", systemImage: "clock")
                            }
                        }

                        DatePicker(
                            "First reminder",
                            selection: startDate,
                            displayedComponents: .hourAndMinute
                        )

                        if preferences.timesPerDay > 1 {
                            DatePicker(
                                "Last reminder",
                                selection: endDate,
                                displayedComponents: .hourAndMinute
                            )
                        }
                    }

                    if preferences.enabled {
                        Button {
                            Task { await sendTestReminder() }
                        } label: {
                            Label("Send a test reminder", systemImage: "bell.badge")
                        }
                    }

                    if notificationsDenied {
                        Label("Allow notifications in Settings → Notifications → German Vocab.", systemImage: "bell.slash")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let reminderStatus {
                        Text(reminderStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text(reminderFooter)
                }

                Section {
                    LabeledContent {
                        Text(AppConfig.apiBaseURL.absoluteString)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("API base URL", systemImage: "link")
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("On a physical iPhone or iPad, point AppConfig.apiBaseURL at your Mac’s LAN IP when the API is not public.")
                }

                Section {
                    Button(role: .destructive) {
                        session.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadLimit() }
            .task { await refreshNotificationStatus() }
            .onChange(of: dailyNewLimit) { _, newValue in
                guard limitReady, newValue != savedLimit else { return }
                Task { await saveLimit(newValue) }
            }
            .onChange(of: preferences) { _, newValue in
                let next = newValue.clamped()
                guard next == newValue else {
                    preferences = next
                    return
                }
                next.save()
                Task {
                    await StudyNotificationScheduler.reschedule()
                    PhoneWatchBridge.shared.syncReminders()
                    await refreshNotificationStatus()
                }
            }
        }
    }

    private var startDate: Binding<Date> {
        Binding(
            get: { date(fromMinutes: preferences.startMinutes) },
            set: { newValue in
                preferences.startMinutes = minutes(from: newValue)
            }
        )
    }

    private var endDate: Binding<Date> {
        Binding(
            get: { date(fromMinutes: preferences.endMinutes) },
            set: { newValue in
                preferences.endMinutes = minutes(from: newValue)
            }
        )
    }

    private func loadLimit() async {
        do {
            let stats = try await session.loadStats()
            savedLimit = stats.dailyNewLimit
            dailyNewLimit = stats.dailyNewLimit
            limitError = nil
        } catch {
            limitError = error.localizedDescription
        }
        limitReady = true
    }

    private func saveLimit(_ limit: Int) async {
        isSavingLimit = true
        defer { isSavingLimit = false }
        do {
            savedLimit = try await session.updateDailyNewLimit(limit)
            dailyNewLimit = savedLimit
            limitError = nil
        } catch {
            dailyNewLimit = savedLimit
            limitError = error.localizedDescription
        }
    }

    private var reminderFooter: String {
        let schedule = "Reminders repeat every day between the first and last time. From 17:00, a reminder mentions your streak when today's session is still unfinished."
        guard preferences.enabled, let next = StudyNotificationScheduler.nextFireDate() else {
            return schedule
        }
        let time = next.formatted(date: .omitted, time: .shortened)
        let when = Calendar.current.isDateInToday(next) ? "today" : "tomorrow"
        return "Next reminder \(when) at \(time). \(schedule)"
    }

    private func sendTestReminder() async {
        reminderStatus = await StudyNotificationScheduler.sendTest()
        PhoneWatchBridge.shared.sendTestReminder()
        PhoneWatchBridge.shared.syncReminders()
        await refreshNotificationStatus()
        if let failure = StudyNotificationScheduler.lastFailure, notificationsDenied == false {
            reminderStatus = failure
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = preferences.enabled && settings.authorizationStatus == .denied
    }

    private func date(fromMinutes minutes: Int) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return Calendar.current.date(from: parts) ?? Date()
    }

    private func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
