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
