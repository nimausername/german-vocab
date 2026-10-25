import SwiftUI

struct WordsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
    @State private var selectedWordID: String?

    private var filtersAreActive: Bool {
        status != .all || gender != .all
    }

    private var selectedWord: LexiconWord? {
        guard let selectedWordID else { return nil }
        return words.first { $0.id == selectedWordID }
    }

    var body: some View {
        if horizontalSizeClass == .compact {
            NavigationStack {
                sidebar
                    .navigationDestination(for: String.self) { id in
                        if let word = words.first(where: { $0.id == id }) {
                            WordDetailView(word: word)
                        }
                    }
            }
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                if let selectedWord {
                    WordDetailView(word: selectedWord)
                } else {
                    ContentUnavailableView(
                        "No word selected",
                        systemImage: "text.book.closed",
                        description: Text("Choose a word from the list.")
                    )
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    private var sidebar: some View {
        Group {
            if isLoading && words.isEmpty {
                ProgressView("Loading words")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, words.isEmpty {
                ContentUnavailableView(
                    "Couldn’t load words",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if words.isEmpty {
                ContentUnavailableView(
                    "No words found",
                    systemImage: "text.book.closed",
                    description: Text("Try another search or filter.")
                )
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
        List(selection: $selectedWordID) {
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
                Text("\(total) words")
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

    @ViewBuilder
    private func wordRow(_ word: LexiconWord) -> some View {
        if horizontalSizeClass == .compact {
            NavigationLink(value: word.id) {
                WordRow(word: word)
            }
        } else {
            WordRow(word: word)
                .tag(word.id)
        }
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
            if let selectedWordID, !words.contains(where: { $0.id == selectedWordID }) {
                self.selectedWordID = nil
            }
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let article = word.article {
                        Text(article)
                            .foregroundStyle(AppTheme.genderColor(for: article))
                    }
                    Text(word.displayNoun)
                        .foregroundStyle(.primary)
                }
                .font(.body)

                Text(word.glossEn)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(word.cefrLevel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(word.progress.learned ? "Learned" : "New")
                    .font(.caption)
                    .foregroundStyle(word.progress.learned ? Color.green : Color.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.headwordWithArticle), \(word.glossEn)")
    }
}
