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

struct StudyItem: Codable, Identifiable {
    let cardId: String
    let wordId: String
    let lemma: String
    let gender: String?
    let plural: String?
    let glossEn: String
    let cefrLevel: String
    let exampleDe: String
    let exampleEn: String
    /// Short German sentence for this word. Empty on servers that do not send one yet.
    let practiceDe: String
    let practiceEn: String
    /// Practice sentence with the target word replaced by `_____`.
    let blankDe: String
    /// The word that fills `blankDe`, including its article when the sentence has one.
    let blankAnswer: String
    /// Young cards write the word from English. Mature cards skip to the blank.
    let recallWord: Bool
    /// Same meaning as `recallWord` on current servers. Kept for older plans.
    let writesSentence: Bool
    let kind: String
    let due: String

    var id: String { cardId }

    var isNew: Bool { kind == "new" }

    enum CodingKeys: String, CodingKey {
        case cardId, wordId, lemma, gender, plural, glossEn, cefrLevel
        case exampleDe, exampleEn, practiceDe, practiceEn, blankDe, blankAnswer
        case recallWord, writesSentence, kind, due
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardId = try container.decode(String.self, forKey: .cardId)
        wordId = try container.decode(String.self, forKey: .wordId)
        lemma = try container.decode(String.self, forKey: .lemma)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        plural = try container.decodeIfPresent(String.self, forKey: .plural)
        glossEn = try container.decode(String.self, forKey: .glossEn)
        cefrLevel = try container.decode(String.self, forKey: .cefrLevel)
        exampleDe = try container.decode(String.self, forKey: .exampleDe)
        exampleEn = try container.decode(String.self, forKey: .exampleEn)
        practiceDe = try container.decodeIfPresent(String.self, forKey: .practiceDe) ?? ""
        practiceEn = try container.decodeIfPresent(String.self, forKey: .practiceEn) ?? ""
        blankDe = try container.decodeIfPresent(String.self, forKey: .blankDe) ?? ""
        blankAnswer = try container.decodeIfPresent(String.self, forKey: .blankAnswer) ?? ""
        let legacyWritesSentence = try container.decodeIfPresent(Bool.self, forKey: .writesSentence) ?? true
        recallWord = try container.decodeIfPresent(Bool.self, forKey: .recallWord) ?? legacyWritesSentence
        writesSentence = legacyWritesSentence
        kind = try container.decode(String.self, forKey: .kind)
        due = try container.decode(String.self, forKey: .due)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cardId, forKey: .cardId)
        try container.encode(wordId, forKey: .wordId)
        try container.encode(lemma, forKey: .lemma)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(plural, forKey: .plural)
        try container.encode(glossEn, forKey: .glossEn)
        try container.encode(cefrLevel, forKey: .cefrLevel)
        try container.encode(exampleDe, forKey: .exampleDe)
        try container.encode(exampleEn, forKey: .exampleEn)
        try container.encode(practiceDe, forKey: .practiceDe)
        try container.encode(practiceEn, forKey: .practiceEn)
        try container.encode(blankDe, forKey: .blankDe)
        try container.encode(blankAnswer, forKey: .blankAnswer)
        try container.encode(recallWord, forKey: .recallWord)
        try container.encode(writesSentence, forKey: .writesSentence)
        try container.encode(kind, forKey: .kind)
        try container.encode(due, forKey: .due)
    }

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

struct TodayPlan: Codable {
    let planDate: String
    let newLimit: Int
    let reviewDue: Int
    let newRemaining: Int
    let queue: [StudyItem]
    let streak: Int
    /// True after at least one review today. Missing on older servers.
    let studiedToday: Bool

    enum CodingKeys: String, CodingKey {
        case planDate, newLimit, reviewDue, newRemaining, queue, streak, studiedToday
    }

    init(
        planDate: String,
        newLimit: Int,
        reviewDue: Int,
        newRemaining: Int,
        queue: [StudyItem],
        streak: Int,
        studiedToday: Bool
    ) {
        self.planDate = planDate
        self.newLimit = newLimit
        self.reviewDue = reviewDue
        self.newRemaining = newRemaining
        self.queue = queue
        self.streak = streak
        self.studiedToday = studiedToday
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planDate = try container.decode(String.self, forKey: .planDate)
        newLimit = try container.decode(Int.self, forKey: .newLimit)
        reviewDue = try container.decode(Int.self, forKey: .reviewDue)
        newRemaining = try container.decode(Int.self, forKey: .newRemaining)
        queue = try container.decode([StudyItem].self, forKey: .queue)
        streak = try container.decode(Int.self, forKey: .streak)
        studiedToday = try container.decodeIfPresent(Bool.self, forKey: .studiedToday) ?? false
    }
}

struct ReviewResult: Codable {
    let cardId: String
    let due: String
    let state: Int
    let reps: Int
    let streak: Int
}

struct DailyLimitUpdate: Decodable {
    let dailyNewLimit: Int
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

struct WordProgress: Decodable, Hashable {
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
        case .new: return "Not Learned"
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
        case .all: return "All"
        case .der, .die, .das: return rawValue
        }
    }
}
