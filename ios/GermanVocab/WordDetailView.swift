import SwiftUI

struct WordDetailView: View {
    let word: LexiconWord

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if let article = word.article {
                            Text(article)
                                .foregroundStyle(AppTheme.genderColor(for: article))
                        }
                        Text(word.displayNoun)
                            .foregroundStyle(.primary)
                    }
                    .font(.system(.largeTitle, design: .serif))

                    Text(word.glossEn)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            Section("Forms") {
                LabeledContent("CEFR", value: word.cefrLevel)
                if let plural = word.plural, !plural.isEmpty {
                    LabeledContent("Plural", value: plural)
                }
                if !word.tags.isEmpty {
                    LabeledContent("Tags", value: word.tags.joined(separator: ", "))
                }
            }

            Section("Examples") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(word.exampleDe)
                        .font(.body.italic())
                    Text(word.exampleEn)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Your progress") {
                LabeledContent("Status") {
                    Text(word.progress.learned ? "Learned" : "Not learned yet")
                        .foregroundStyle(word.progress.learned ? Color.green : Color.orange)
                }
                LabeledContent("Reviews", value: "\(word.progress.reps)")
                LabeledContent("Lapses", value: "\(word.progress.lapses)")
                if let due = word.progress.due {
                    LabeledContent("Next due", value: formatDate(due))
                }
                if let last = word.progress.lastReview {
                    LabeledContent("Last review", value: formatDate(last))
                }
            }
        }
        .navigationTitle(word.headwordWithArticle)
        .navigationBarTitleDisplayMode(.inline)
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
