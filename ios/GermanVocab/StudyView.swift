import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var queue: [StudyItem]
    @State private var initialCount: Int
    @State private var revealed = false
    @State private var startedAt = Date()
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    init(initialQueue: [StudyItem]) {
        _queue = State(initialValue: initialQueue)
        _initialCount = State(initialValue: max(initialQueue.count, 1))
    }

    private var completed: Int {
        max(0, initialCount - queue.count)
    }

    private var progress: Double {
        Double(completed) / Double(initialCount)
    }

    var body: some View {
        Group {
            if let current = queue.first {
                activeSession(current)
            } else {
                sessionComplete
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.wash)
        .navigationTitle("Study")
        .navigationBarTitleDisplayMode(.inline)
        .animation(AppTheme.reveal, value: revealed)
        .animation(AppTheme.reveal, value: queue.first?.cardId)
        .tint(AppTheme.accent)
    }

    private func activeSession(_ current: StudyItem) -> some View {
        VStack(spacing: 24) {
            sessionChrome

            Spacer(minLength: 0)

            cardBody(current)
                .frame(maxWidth: 560)

            Spacer(minLength: 0)

            if revealed {
                ratingRow(for: current)
                    .frame(maxWidth: sizeClass == .regular ? 640 : .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Button("Show answer") {
                    withAnimation(AppTheme.reveal) { revealed = true }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.ink)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel("Show answer")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
            }
        }
        .padding(24)
    }

    private var sessionChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(queue.count) left")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text("\(completed) / \(initialCount)")
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.inkSoft)
                    .monospacedDigit()
            }
            ProgressRail(progress: progress)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func cardBody(_ current: StudyItem) -> some View {
        VStack(spacing: 18) {
            KindLabel(isNew: current.isNew)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let article = current.article {
                    Text(article)
                        .font(AppTheme.lemma(56))
                        .foregroundStyle(AppTheme.genderColor(for: article))
                }

                Text(current.displayNoun)
                    .font(AppTheme.lemma(56))
                    .foregroundStyle(AppTheme.ink)
                    .minimumScaleFactor(0.65)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(current.headwordWithArticle)

            if revealed {
                VStack(spacing: 16) {
                    Divider()
                        .padding(.horizontal, 48)

                    Text(current.glossEn)
                        .font(AppTheme.display(28, weight: .medium))
                        .foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.center)

                    if let article = current.article {
                        Text(current.headwordWithArticle)
                            .font(AppTheme.headline())
                            .foregroundStyle(AppTheme.genderColor(for: article))
                            .accessibilityLabel("Remember: \(current.headwordWithArticle)")
                    }

                    if let plural = current.plural, !plural.isEmpty {
                        Text("Plural: \(plural)")
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.inkSoft)
                    }

                    VStack(spacing: 8) {
                        Text(current.exampleDe)
                            .font(AppTheme.body().italic())
                            .multilineTextAlignment(.center)
                        Text(current.exampleEn)
                            .font(AppTheme.caption())
                            .foregroundStyle(AppTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var sessionComplete: some View {
        ContentUnavailableView(
            "Session complete",
            systemImage: "checkmark.circle",
            description: Text("Great work. Come back tomorrow for the next set.")
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Back to Today") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.ink)
                .padding()
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
        }
    }

    private func ratingRow(for item: StudyItem) -> some View {
        HStack(spacing: 12) {
            RatingKey(title: "Again", hint: "1", tint: AppTheme.danger, disabled: isSubmitting) {
                Task { await submit(rating: .again, item: item) }
            }
            .keyboardShortcut("1", modifiers: [])

            RatingKey(title: "Hard", hint: "2", tint: AppTheme.warning, disabled: isSubmitting) {
                Task { await submit(rating: .hard, item: item) }
            }
            .keyboardShortcut("2", modifiers: [])

            RatingKey(title: "Good", hint: "3", tint: AppTheme.der, disabled: isSubmitting) {
                Task { await submit(rating: .good, item: item) }
            }
            .keyboardShortcut("3", modifiers: [])

            RatingKey(title: "Easy", hint: "4", tint: AppTheme.positive, disabled: isSubmitting) {
                Task { await submit(rating: .easy, item: item) }
            }
            .keyboardShortcut("4", modifiers: [])
        }
        .disabled(isSubmitting)
    }

    private func submit(rating: Rating, item: StudyItem) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        do {
            _ = try await session.submitReview(
                cardId: item.cardId,
                rating: rating,
                durationMs: durationMs
            )
            if !queue.isEmpty {
                queue.removeFirst()
            }
            revealed = false
            startedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
