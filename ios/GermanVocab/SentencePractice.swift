import Foundation

struct PracticeSentence: Equatable {
    let german: String
    let english: String
}

/// Picks the sentence the learner writes.
///
/// The server sentence is used when the plan includes one. Otherwise a short
/// frame is built on device so the step still asks for a full sentence.
enum SentencePractice {
    static func resolve(_ item: StudyItem) -> PracticeSentence {
        let german = item.practiceDe.trimmingCharacters(in: .whitespacesAndNewlines)
        let english = item.practiceEn.trimmingCharacters(in: .whitespacesAndNewlines)
        if !german.isEmpty, !english.isEmpty, !isShallowTemplate(german) {
            return PracticeSentence(german: german, english: english)
        }
        return fallback(for: item)
    }

    private static let early: [String: PracticeSentence] = [
        "ich": PracticeSentence(german: "Das bin ich.", english: "That is me."),
        "du": PracticeSentence(german: "Das bist du.", english: "That is you."),
        "er": PracticeSentence(german: "Das ist er.", english: "That is him."),
        "sie": PracticeSentence(german: "Das ist sie.", english: "That is her."),
        "wir": PracticeSentence(german: "Das sind wir.", english: "That is us."),
        "ihr": PracticeSentence(german: "Das seid ihr.", english: "That is you."),
        "sein": PracticeSentence(german: "Ich bin da.", english: "I am here."),
        "haben": PracticeSentence(german: "Ich habe das.", english: "I have that."),
        "werden": PracticeSentence(german: "Ich werde das.", english: "I will do that."),
        "können": PracticeSentence(german: "Ich kann das.", english: "I can do that."),
        "müssen": PracticeSentence(german: "Ich muss das.", english: "I have to do that."),
        "wollen": PracticeSentence(german: "Ich will das.", english: "I want that."),
        "mögen": PracticeSentence(german: "Ich mag das.", english: "I like that."),
        "dürfen": PracticeSentence(german: "Ich darf das.", english: "I may do that."),
        "sollen": PracticeSentence(german: "Ich soll das.", english: "I am supposed to."),
    ]

    private static func fallback(for item: StudyItem) -> PracticeSentence {
        if isDailyExample(item.exampleDe) {
            return PracticeSentence(german: item.exampleDe, english: item.exampleEn)
        }

        if item.article != nil {
            return dailyNoun(item)
        }

        if item.glossEn.lowercased().hasPrefix("to ") {
            let verb = plainGloss(item.glossEn).replacingOccurrences(
                of: "^to\\s+",
                with: "",
                options: .regularExpression
            )
            return PracticeSentence(
                german: "Ich möchte \(item.lemma).",
                english: "I would like to \(verb)."
            )
        }

        if isCopulaOnly(item.exampleDe) {
            let gloss = plainGloss(item.glossEn)
            return PracticeSentence(
                german: "Das finde ich \(item.lemma).",
                english: "I find that \(gloss)."
            )
        }

        if let known = early[item.lemma] {
            return known
        }

        let exampleWords = wordCount(item.exampleDe)
        if exampleWords >= 2, exampleWords <= 6, containsLemma(item.exampleDe, item: item) {
            return PracticeSentence(german: item.exampleDe, english: item.exampleEn)
        }

        let gloss = plainGloss(item.glossEn)
        if !item.lemma.contains(" ") {
            return PracticeSentence(
                german: "Ich bin \(item.lemma) da.",
                english: "I am here \(gloss)."
            )
        }

        return PracticeSentence(
            german: "Das ist \(item.lemma).",
            english: "That is \(gloss)."
        )
    }

    /// Where is / I see / I need. Stable for a lemma, and not “Das ist …”.
    private static func dailyNoun(_ item: StudyItem) -> PracticeSentence {
        let gloss = plainGloss(item.glossEn)
        let nominative = item.headwordWithArticle
        let object = item.article == "der" ? "den \(item.displayNoun)" : nominative
        let frames = [
            PracticeSentence(german: "Wo ist \(nominative)?", english: "Where is the \(gloss)?"),
            PracticeSentence(german: "Ich sehe \(object).", english: "I see the \(gloss)."),
            PracticeSentence(german: "Ich brauche \(object).", english: "I need the \(gloss)."),
        ]
        let index = item.lemma.unicodeScalars.reduce(0) { $0 + Int($1.value) } % frames.count
        return frames[index]
    }

    private static func isDailyExample(_ sentence: String) -> Bool {
        let count = wordCount(sentence)
        guard count >= 2, count <= 8 else { return false }
        return !isBoilerplate(sentence)
    }

    private static func isBoilerplate(_ sentence: String) -> Bool {
        let value = sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        if value.contains("für viele menschen") || value.contains("ist wichtig") || value.contains("bleibt wichtig") {
            return true
        }
        let parts = value.split(separator: " ")
        return parts.count == 3 && parts[0] == "das" && parts[1] == "ist"
    }

    /// Old plans used “Das ist der …” and “Ich kann …” for almost every card.
    private static func isShallowTemplate(_ sentence: String) -> Bool {
        if isBoilerplate(sentence) {
            return true
        }
        let value = sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if value.hasPrefix("das ist der ") || value.hasPrefix("das ist die ") || value.hasPrefix("das ist das ") {
            return true
        }
        return value.hasPrefix("ich kann ")
    }

    private static func isCopulaOnly(_ sentence: String) -> Bool {
        isBoilerplate(sentence) && sentence.lowercased().hasPrefix("das ist ")
    }

    private static func plainGloss(_ gloss: String) -> String {
        var value = gloss
        if let open = value.range(of: " (") {
            value = String(value[..<open.lowerBound])
        }
        if let slash = value.range(of: "/") {
            value = String(value[..<slash.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wordCount(_ sentence: String) -> Int {
        sentence
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
            .count
    }

    private static func containsLemma(_ sentence: String, item: StudyItem) -> Bool {
        let haystack = ClozeSupport.normalize(sentence)
        let needle = ClozeSupport.normalize(item.displayNoun)
        return !needle.isEmpty && haystack.contains(needle)
    }
}
