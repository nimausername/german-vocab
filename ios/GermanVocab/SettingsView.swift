import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var dailyNewLimit = 8
    @State private var savedLimit = 8
    @State private var limitReady = false
    @State private var isSavingLimit = false
    @State private var limitError: String?

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var savedFirstName = ""
    @State private var savedLastName = ""
    @State private var isSavingProfile = false
    @State private var profileError: String?
    @State private var profileStatus: String?

    @State private var studyFilters = StudyFilters.default
    @State private var savedFilters = StudyFilters.default
    @State private var isSavingFilters = false
    @State private var filterError: String?

    @State private var preferences = ReminderPreferences.load()
    @State private var notificationsDenied = false
    @State private var reminderStatus: String?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportShare: ExportShareItem?

    private let cefrOptions = ["A1", "A2", "B1", "B2", "C1"]
    private let tagOptions = ["noun", "verb", "adjective", "adverb", "function"]

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
                    Toggle("Nouns only", isOn: $studyFilters.nounsOnly)

                    ForEach(cefrOptions, id: \.self) { level in
                        Toggle(level, isOn: cefrBinding(level))
                    }

                    ForEach(tagOptions, id: \.self) { tag in
                        Toggle(tag.capitalized, isOn: tagBinding(tag))
                    }

                    if isSavingFilters {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Saving filters")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let filterError {
                        Text(filterError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Study Filters")
                } footer: {
                    Text("Empty CEFR and tag lists mean all levels and tags. Filters apply the next time Today loads.")
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
                    Button {
                        Task { await exportProgress(format: .csv) }
                    } label: {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                    .disabled(isExporting)

                    Button {
                        Task { await exportProgress(format: .anki) }
                    } label: {
                        Label("Export Anki deck", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting)

                    if isExporting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparing export")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let exportError {
                        Text(exportError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("CSV keeps full progress fields. Anki is a tab-separated file you can import as notes (German → English).")
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
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)

                    Button {
                        Task { await saveProfile() }
                    } label: {
                        if isSavingProfile {
                            ProgressView()
                        } else {
                            Text("Save name")
                        }
                    }
                    .disabled(!canSaveProfile || isSavingProfile)

                    if let profileStatus {
                        Text(profileStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let profileError {
                        Text(profileError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button(role: .destructive) {
                        SharedStudySnapshot.clear()
                        session.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Your name appears in Today’s welcome line.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadSettings() }
            .task { await refreshNotificationStatus() }
            .onChange(of: dailyNewLimit) { _, newValue in
                guard limitReady, newValue != savedLimit else { return }
                Task { await saveLimit(newValue) }
            }
            .onChange(of: studyFilters) { _, newValue in
                guard limitReady, newValue != savedFilters else { return }
                Task { await saveFilters(newValue) }
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
            .sheet(item: $exportShare) { item in
                ActivityShareView(items: [item.url])
            }
        }
    }

    private var canSaveProfile: Bool {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !last.isEmpty else { return false }
        return first != savedFirstName || last != savedLastName
    }

    private func cefrBinding(_ level: String) -> Binding<Bool> {
        Binding(
            get: { studyFilters.cefrLevels.contains(level) },
            set: { enabled in
                var next = studyFilters.cefrLevels
                if enabled {
                    if !next.contains(level) { next.append(level) }
                } else {
                    next.removeAll { $0 == level }
                }
                studyFilters.cefrLevels = next.sorted()
            }
        )
    }

    private func tagBinding(_ tag: String) -> Binding<Bool> {
        Binding(
            get: { studyFilters.tags.contains(tag) },
            set: { enabled in
                var next = studyFilters.tags
                if enabled {
                    if !next.contains(tag) { next.append(tag) }
                } else {
                    next.removeAll { $0 == tag }
                }
                studyFilters.tags = next.sorted()
            }
        )
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

    private func loadSettings() async {
        do {
            let settings = try await session.loadSettings()
            savedLimit = settings.dailyNewLimit
            dailyNewLimit = settings.dailyNewLimit
            firstName = settings.firstName ?? ""
            lastName = settings.lastName ?? ""
            savedFirstName = firstName
            savedLastName = lastName
            studyFilters = settings.studyFilters
            savedFilters = settings.studyFilters
            limitError = nil
            profileError = nil
            filterError = nil
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

    private func saveFilters(_ filters: StudyFilters) async {
        isSavingFilters = true
        defer { isSavingFilters = false }
        do {
            let settings = try await session.updateStudyFilters(filters)
            savedFilters = settings.studyFilters
            studyFilters = settings.studyFilters
            filterError = nil
        } catch {
            studyFilters = savedFilters
            filterError = error.localizedDescription
        }
    }

    private func saveProfile() async {
        isSavingProfile = true
        defer { isSavingProfile = false }
        profileError = nil
        profileStatus = nil
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let settings = try await session.updateProfileName(firstName: first, lastName: last)
            firstName = settings.firstName ?? first
            lastName = settings.lastName ?? last
            savedFirstName = firstName
            savedLastName = lastName
            profileStatus = "Name saved."
        } catch {
            profileError = error.localizedDescription
        }
    }

    private var reminderFooter: String {
        let schedule = "Reminders repeat every day between the first and last time. Later reminders mention your streak when today’s goal is still open. The Apple Watch schedules the same alerts so they still show when the iPhone is locked."
        guard preferences.enabled, let next = StudyNotificationScheduler.nextFireDate() else {
            return schedule
        }
        let time = next.formatted(date: .omitted, time: .shortened)
        let when = Calendar.current.isDateInToday(next) ? "today" : "tomorrow"
        return "Next reminder \(when) at \(time). \(schedule)"
    }

    private func exportProgress(format: ProgressExportFormat) async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            let payload = try await session.exportProgress(format: format)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(payload.filename)
            try payload.content.write(to: url, atomically: true, encoding: .utf8)
            exportShare = ExportShareItem(url: url)
        } catch {
            exportError = error.localizedDescription
        }
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
