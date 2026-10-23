import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let data: T
}

struct TokenPayload: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let refreshExpiresIn: Int?
    let tokenType: String
}

struct StudyItem: Decodable, Identifiable {
    let cardId: String
    let wordId: String
    let lemma: String
    let gender: String?
    let plural: String?
    let glossEn: String
    let cefrLevel: String
    let exampleDe: String
    let exampleEn: String
    let kind: String
    let due: String

    var id: String { cardId }

    var isNew: Bool { kind == "new" }

    /// Normalized article for nouns: der / die / das.
    var article: String? {
        guard let gender else { return nil }
        switch gender.lowercased() {
        case "der", "m", "masculine": return "der"
        case "die", "f", "feminine": return "die"
        case "das", "n", "neuter": return "das"
        default:
            let trimmed = gender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["der", "die", "das"].contains(trimmed) ? trimmed : nil
        }
    }

    /// Noun without a leading article if the lemma already includes one.
    var displayNoun: String {
        let trimmed = lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return trimmed }
        let first = parts[0].lowercased()
        if ["der", "die", "das"].contains(first) {
            return String(parts[1])
        }
        return trimmed
    }

    /// Full headword with article when available, e.g. "die Stadt".
    var headwordWithArticle: String {
        if let article {
            return "\(article) \(displayNoun)"
        }
        return lemma
    }
}

struct TodayPlan: Decodable {
    let planDate: String
    let newLimit: Int
    let reviewDue: Int
    let newRemaining: Int
    let queue: [StudyItem]
    let streak: Int
}

struct ReviewResult: Decodable {
    let cardId: String
    let due: String
    let state: Int
    let reps: Int
    let streak: Int
}

struct UserStats: Decodable {
    let streak: Int
    let dailyNewLimit: Int
    let wordsLearned: Int
    let wordsTotal: Int
    let reviewsDueNext7Days: Int
    let reviewsToday: Int
    let matureCards: Int
}

struct APIErrorBody: Decodable {
    struct ErrorPayload: Decodable {
        let code: String
        let message: String
    }

    let error: ErrorPayload
}

enum Rating: Int {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

struct WordProgress: Decodable {
    let learned: Bool
    let cardId: String?
    let reps: Int
    let lapses: Int
    let state: Int?
    let due: String?
    let lastReview: String?
}

struct LexiconWord: Decodable, Identifiable, Hashable {
    let id: String
    let lemma: String
    let gender: String?
    let plural: String?
    let glossEn: String
    let cefrLevel: String
    let exampleDe: String
    let exampleEn: String
    let sortOrder: Int
    let tags: [String]
    let progress: WordProgress

    var article: String? {
        guard let gender else { return nil }
        switch gender.lowercased() {
        case "der", "m", "masculine": return "der"
        case "die", "f", "feminine": return "die"
        case "das", "n", "neuter": return "das"
        default:
            let trimmed = gender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["der", "die", "das"].contains(trimmed) ? trimmed : nil
        }
    }

    var displayNoun: String {
        let trimmed = lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return trimmed }
        let first = parts[0].lowercased()
        if ["der", "die", "das"].contains(first) {
            return String(parts[1])
        }
        return trimmed
    }

    var headwordWithArticle: String {
        if let article {
            return "\(article) \(displayNoun)"
        }
        return lemma
    }
}

struct WordListPage: Decodable {
    let items: [LexiconWord]
    let page: Int
    let limit: Int
    let total: Int
    let hasMore: Bool
}

enum WordListStatus: String, CaseIterable, Identifiable {
    case all
    case learned
    case new

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .learned: return "Learned"
        case .new: return "Not learned"
        }
    }
}

enum WordGenderFilter: String, CaseIterable, Identifiable {
    case all = ""
    case der
    case die
    case das

    var id: String { rawValue.isEmpty ? "all" : rawValue }

    var title: String {
        switch self {
        case .all: return "All articles"
        case .der, .die, .das: return rawValue
        }
    }
}
