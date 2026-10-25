import SwiftUI

struct WatchStudyView: View {
    @ObservedObject var model: WatchStudyModel

    var body: some View {
        Group {
            if !model.isSignedIn {
                signedOut
            } else if model.isLoading && model.current == nil {
                ProgressView("Loading")
            } else if let item = model.current {
                card(item)
            } else {
                ContentUnavailableView {
                    Label("All done", systemImage: "checkmark.circle")
                } description: {
                    Text("Come back tomorrow for the next set.")
                }
            }
        }
        .task { model.start() }
    }

    private var signedOut: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.title2)
                .accessibilityHidden(true)
            Text("Open German Vocab on your iPhone and stay signed in.")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func card(_ item: StudyItem) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(model.queue.count == 1 ? "1 word" : "\(model.queue.count) words")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                headword(item)

                if model.revealed {
                    meaningCard(item)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button("Learned") {
                        Task { await model.mark(learned: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Mark \(item.headwordWithArticle) as learned")

                    Button("Not yet") {
                        Task { await model.mark(learned: false) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Mark \(item.headwordWithArticle) as not yet learned")
                } else {
                    Button {
                        withAnimation(.spring(duration: 0.35)) {
                            model.revealed = true
                        }
                    } label: {
                        Label("Show meaning", systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Reveals the English meaning")
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func headword(_ item: StudyItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let article = item.article {
                Text(article)
                    .foregroundStyle(AppTheme.genderColor(for: article))
            }
            Text(item.displayNoun)
                .foregroundStyle(.primary)
        }
        .font(.system(.title3, design: .serif))
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.headwordWithArticle)
    }

    private func meaningCard(_ item: StudyItem) -> some View {
        let tint = AppTheme.genderColor(for: item.article)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Meaning")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
                .tracking(0.8)

            Text(item.glossEn)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.75)

            if !item.exampleDe.isEmpty {
                Text(item.exampleDe)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meaning, \(item.glossEn). \(item.exampleDe)")
    }
}
