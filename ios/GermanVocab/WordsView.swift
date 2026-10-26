import SwiftUI

struct WordsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var words: [LexiconWord] = []
    @State private var total = 0
    @State private var page = 1
    @State private var hasMore = false
    @State private var searchText = ""
    @State private var status: WordListStatus = .all
    @State private var gender: WordGenderFilter = .all
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    private var filtersAreActive: Bool {
        status != .all || gender != .all
    }

    var body: some View {
        NavigationStack {
            sidebar
        }
    }

    private var sidebar: some View {
        Group {
            if isLoading && words.isEmpty {
                LoadingView(message: "Loading words")
            } else if let errorMessage, words.isEmpty {
                LoadFailureView(title: "Couldn’t load words", message: errorMessage) {
                    Task { await reload() }
                }
            } else if words.isEmpty {
                ContentUnavailableView {
                    Label("No words found", systemImage: "text.book.closed")
                } description: {
                    Text("Try another search or filter.")
                } actions: {
                    if filtersAreActive || !searchText.isEmpty {
                        Button("Clear Search and Filters") {
                            searchText = ""
                            status = .all
                            gender = .all
                        }
                        .glassCapsule(size: .regular)
                    }
                }
            } else {
                wordList
            }
        }
        .navigationTitle("Words")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search German or English")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .task(id: filterKey) {
            await reload()
        }
        .refreshable { await reload() }
    }

    private var filterKey: String {
        "\(status.rawValue)|\(gender.rawValue)|\(searchText)"
    }

    private var filterMenu: some View {
        Menu {
            if filtersAreActive {
                Button("Clear Filters", systemImage: "xmark.circle") {
                    status = .all
                    gender = .all
                }
            }

            Picker("Status", selection: $status) {
                ForEach(WordListStatus.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.inline)

            Picker("Article", selection: $gender) {
                ForEach(WordGenderFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                "Filter",
                systemImage: filtersAreActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityValue("\(status.title), \(gender.title)")
    }

    private var wordList: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(words) { word in
                    wordRow(word)
                        .onAppear {
                            if word.id == words.last?.id {
                                Task { await loadMore() }
                            }
                        }
                }
            } header: {
                Text("\(total.formatted()) words")
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }

    private func wordRow(_ word: LexiconWord) -> some View {
        NavigationLink {
            WordDetailView(word: word)
        } label: {
            WordRow(word: word)
        }
        .accessibilityHint("Opens details for \(word.headwordWithArticle)")
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await session.loadWords(
                page: 1,
                limit: 50,
                search: searchText,
                gender: gender == .all ? nil : gender.rawValue,
                status: status
            )
            words = result.items
            total = result.total
            page = result.page
            hasMore = result.hasMore
        } catch {
            errorMessage = error.localizedDescription
            words = []
            total = 0
            hasMore = false
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = page + 1
            let result = try await session.loadWords(
                page: nextPage,
                limit: 50,
                search: searchText,
                gender: gender == .all ? nil : gender.rawValue,
                status: status
            )
            words.append(contentsOf: result.items)
            total = result.total
            page = result.page
            hasMore = result.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WordRow: View {
    let word: LexiconWord

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ArticleText(article: word.article)
                    Text(word.displayNoun)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Text(word.glossEn)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(word.cefrLevel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: Capsule())

                StatusChip(
                    title: word.progress.learned ? "Learned" : "New",
                    tint: word.progress.learned ? .green : .orange,
                    systemImage: word.progress.learned ? "checkmark" : "sparkle"
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.headwordWithArticle), \(word.glossEn)")
    }
}
