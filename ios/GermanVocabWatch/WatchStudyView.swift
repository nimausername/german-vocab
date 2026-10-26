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
            } else if model.errorMessage != nil {
                loadFailed
            } else {
                finished
            }
        }
        .task { model.start() }
    }

    private var finished: some View {
        ScrollView {
            ContentUnavailableView {
                Label("All done", systemImage: "checkmark.circle")
            } description: {
                Text("Come back tomorrow for the next set.")
            }
        }
        .refreshable { await model.load(force: true) }
    }

    private var loadFailed: some View {
        VStack(spacing: 8) {
            Text(model.errorMessage ?? "Couldn’t load today’s words.")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await model.load(force: true) }
            }
            .modifier(WatchActionStyle(prominent: true))
        }
        .padding(.horizontal, 4)
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

                Text("Reading practice only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                headword(item)

                if model.revealed {
                    meaningCard(item)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))

                    Button("Learned") {
                        Task { await model.mark(learned: true) }
                    }
                    .modifier(WatchActionStyle(prominent: true))
                    .tint(.green)
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Mark \(item.headwordWithArticle) as learned")

                    Button("Not yet") {
                        Task { await model.mark(learned: false) }
                    }
                    .modifier(WatchActionStyle(prominent: false))
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
                    .modifier(WatchActionStyle(prominent: true))
                    .accessibilityHint("Reveals the English meaning")
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 2)
        }
        .refreshable { await model.load(force: true) }
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

    private func exampleSentence(_ item: StudyItem) -> String {
        let practice = item.practiceDe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !practice.isEmpty, !Self.isShallowTemplate(practice) {
            return practice
        }
        return item.exampleDe
    }

    private static func isShallowTemplate(_ sentence: String) -> Bool {
        let value = sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("das ist der ") || value.hasPrefix("das ist die ") || value.hasPrefix("das ist das ") {
            return true
        }
        if value.hasPrefix("ich kann ") || value.contains("ist wichtig") || value.contains("für viele menschen") {
            return true
        }
        return false
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

            if !exampleSentence(item).isEmpty {
                Text(exampleSentence(item))
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
        .accessibilityLabel("Meaning, \(item.glossEn). \(exampleSentence(item))")
    }
}

/// Glass on watchOS 26, and the standard bordered styles on earlier watches.
private struct WatchActionStyle: ViewModifier {
    var prominent: Bool

    func body(content: Content) -> some View {
        if #available(watchOS 26, *) {
            if prominent {
                content
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            } else {
                content
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
