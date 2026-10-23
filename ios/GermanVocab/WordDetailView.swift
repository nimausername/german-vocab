import SwiftUI

struct WordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let word: LexiconWord

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if let article = word.article {
                                Text(article)
                                    .font(AppTheme.lemma(40))
                                    .foregroundStyle(AppTheme.genderColor(for: article))
                            }
                            Text(word.displayNoun)
                                .font(AppTheme.lemma(40))
                                .foregroundStyle(AppTheme.ink)
                        }

                        Text(word.glossEn)
                            .font(AppTheme.display(22, weight: .medium))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .padding(.vertical, 6)
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(word.exampleDe)
                            .font(AppTheme.body().italic())
                        Text(word.exampleEn)
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.vertical, 4)
                }

                Section("Your progress") {
                    LabeledContent("Status", value: word.progress.learned ? "Learned" : "Not learned yet")
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
            .listStyle(.insetGrouped)
            .navigationTitle("Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Done")
                }
            }
            .tint(AppTheme.accent)
        }
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
