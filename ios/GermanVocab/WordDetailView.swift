import SwiftUI

struct WordDetailView: View {
    let word: LexiconWord
    @StateObject private var speaker = GermanSpeaker()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 8) {
                        ArticleText(article: word.article, prominent: true)
                        Text(word.cefrLevel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.fill.tertiary, in: Capsule())
                        Spacer(minLength: 8)
                        StatusChip(
                            title: word.progress.learned ? "Learned" : "New",
                            tint: word.progress.learned ? AppTheme.accent : .orange,
                            systemImage: word.progress.learned ? "checkmark" : "sparkle"
                        )
                    }

                    Text(word.displayNoun)
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(.primary)

                    Text(word.glossEn)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    SpeakGermanButton(speaker: speaker, text: word.headwordWithArticle, size: .regular)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(word.headwordWithArticle), \(word.glossEn)")
            }

            Section("Study sentence") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(word.practiceDe)
                        .font(.body.weight(.semibold))
                    Text(word.practiceEn)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SpeakGermanButton(speaker: speaker, text: word.practiceDe, size: .small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            if word.exampleDe != word.practiceDe {
                Section("Dictionary example") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(word.exampleDe)
                            .font(.body.italic())
                        Text(word.exampleEn)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }

            Section("Forms") {
                if let plural = word.plural, !plural.isEmpty, plural != "-" {
                    MetricRow(title: "Plural", value: plural, systemImage: "textformat")
                }
                if !word.tags.isEmpty {
                    MetricRow(title: "Tags", value: word.tags.joined(separator: ", "), systemImage: "tag")
                }
            }

            Section("Your progress") {
                MetricRow(title: "Reviews", value: "\(word.progress.reps)", systemImage: "arrow.clockwise")
                MetricRow(title: "Lapses", value: "\(word.progress.lapses)", systemImage: "arrow.uturn.backward")
                if let due = word.progress.due {
                    MetricRow(title: "Next due", value: formatDate(due), systemImage: "calendar")
                } else {
                    MetricRow(title: "Next due", value: "Not started", systemImage: "calendar")
                }
                if let last = word.progress.lastReview {
                    MetricRow(title: "Last review", value: formatDate(last), systemImage: "clock")
                }
            }
        }
        .navigationTitle(word.headwordWithArticle)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stop() }
    }

    private func formatDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        let date = parser.date(from: iso) ?? fallback.date(from: iso)
        guard let date else { return iso }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
