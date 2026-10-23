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
    @State private var selectedWord: LexiconWord?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && words.isEmpty {
                    ProgressView("Loading words")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if words.isEmpty, errorMessage == nil {
                    ContentUnavailableView(
                        "No words found",
                        systemImage: "text.book.closed",
                        description: Text("Try another search or filter.")
                    )
                } else {
                    wordList
                }
            }
            .background(AppTheme.wash)
            .navigationTitle("Words")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search German or English")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(total)")
                        .font(AppTheme.caption())
                        .foregroundStyle(AppTheme.muted)
                        .accessibilityLabel("\(total) words")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
            }
            .task(id: filterKey) {
                await reload()
            }
            .refreshable { await reload() }
            .sheet(item: $selectedWord) { word in
                WordDetailView(word: word)
            }
            .tint(AppTheme.accent)
        }
    }

    private var filterKey: String {
        "\(status.rawValue)|\(gender.rawValue)|\(searchText)"
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(WordListStatus.allCases) { item in
                    FilterChip(
                        title: item.title,
                        isSelected: status == item
                    ) {
                        status = item
                    }
                }

                Divider()
                    .frame(height: 20)

                ForEach(WordGenderFilter.allCases) { item in
                    FilterChip(
                        title: item.title,
                        isSelected: gender == item,
                        tint: item == .all ? AppTheme.accent : AppTheme.genderColor(for: item.rawValue)
                    ) {
                        gender = item
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppTheme.wash.opacity(0.98))
    }

    private var wordList: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.danger)
            }

            ForEach(words) { word in
                Button {
                    selectedWord = word
                } label: {
                    WordRow(word: word)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if word.id == words.last?.id {
                        Task { await loadMore() }
                    }
                }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.insetGrouped)
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

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var tint: Color = AppTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.caption())
                .foregroundStyle(isSelected ? .white : AppTheme.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? tint : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WordRow: View {
    let word: LexiconWord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let article = word.article {
                        Text(article)
                            .font(AppTheme.headline())
                            .foregroundStyle(AppTheme.genderColor(for: article))
                    }
                    Text(word.displayNoun)
                        .font(AppTheme.headline())
                        .foregroundStyle(AppTheme.ink)
                }

                Text(word.glossEn)
                    .font(AppTheme.caption())
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(word.cefrLevel)
                    .font(AppTheme.micro())
                    .foregroundStyle(AppTheme.muted)

                Text(word.progress.learned ? "Learned" : "New")
                    .font(AppTheme.micro())
                    .foregroundStyle(word.progress.learned ? AppTheme.positive : AppTheme.warning)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.headwordWithArticle), \(word.glossEn)")
    }
}
