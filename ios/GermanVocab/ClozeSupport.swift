import Foundation

struct ClozePrompt {
    /// Sentence with `_____` in place of the target.
    let blankedSentence: String
    /// Exact span removed from the example (best target for the learner).
    let expected: String
    /// True only when the blanked span includes der/die/das.
    let requiresArticle: Bool
    /// Placeholder hint for the text field.
    let inputHint: String
}

enum ClozeResult: Equatable {
    case full
    case partial(missingArticle: String)
    case wrong
}

enum ClozeSupport {
    private static let fallbackDistractors = [
        "ich", "du", "er", "sie", "wir", "ihr",
        "sein", "haben", "gehen", "kommen", "machen",
        "der Mann", "die Frau", "das Kind", "die Stadt", "das Haus",
    ]

    /// Builds a cloze prompt from the word's example sentence.
    static func makePrompt(for item: StudyItem) -> ClozePrompt {
        let source = item.exampleDe.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = blankCandidates(for: item).sorted { $0.count > $1.count }

        for candidate in candidates {
            if let match = firstMatch(of: candidate, in: source) {
                let blanked = source.replacingCharacters(in: match.range, with: "_____")
                let requiresArticle = spanIncludesArticle(match.text)
                return ClozePrompt(
                    blankedSentence: blanked,
                    expected: match.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    requiresArticle: requiresArticle,
                    inputHint: requiresArticle
                        ? "Type what fits the blank (include article)"
                        : "Type what fits the blank"
                )
            }
        }

        let expected = item.displayNoun
        return ClozePrompt(
            blankedSentence: "_____",
            expected: expected,
            requiresArticle: false,
            inputHint: "Type the German word"
        )
    }

    /// Multiple-choice options for the blank (includes the expected answer).
    static func choices(prompt: ClozePrompt, item: StudyItem, pool: [StudyItem]) -> [String] {
        let correct = prompt.expected.trimmingCharacters(in: .whitespacesAndNewlines)
        var options: [String] = [correct]
        var seen = Set([normalize(correct), compactKey(correct)])

        func add(_ raw: String) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            let key = normalize(value)
            let compact = compactKey(value)
            guard !seen.contains(key), !seen.contains(compact) else { return }
            seen.insert(key)
            seen.insert(compact)
            options.append(value)
        }

        // Same noun with wrong articles (German-specific useful distractors).
        if let article = item.article {
            for other in ["der", "die", "das"] where other != article {
                add("\(other) \(item.displayNoun)")
            }
        }

        for other in pool where other.wordId != item.wordId {
            add(other.article == nil ? other.displayNoun : other.headwordWithArticle)
            add(other.displayNoun)
            if options.count >= 4 { break }
        }

        for filler in fallbackDistractors {
            add(filler)
            if options.count >= 4 { break }
        }

        return Array(options.prefix(4)).shuffled()
    }

    static func evaluate(answer: String, prompt: ClozePrompt, item: StudyItem) -> ClozeResult {
        let answerKey = normalize(answer)
        guard !answerKey.isEmpty else { return .wrong }

        let expectedKey = normalize(prompt.expected)
        let compactAnswer = compactKey(answer)
        let compactExpected = compactKey(prompt.expected)

        // Exact blank match wins (choice buttons send this exact string).
        if answer.trimmingCharacters(in: .whitespacesAndNewlines) == prompt.expected.trimmingCharacters(in: .whitespacesAndNewlines) {
            return .full
        }

        let matchesExpected =
            answerKey == expectedKey
            || compactAnswer == compactExpected

        let matchesAccepted = acceptedAnswers(prompt: prompt, item: item)
            .contains { normalize($0) == answerKey || compactKey($0) == compactAnswer }

        guard matchesExpected || matchesAccepted else { return .wrong }

        if prompt.requiresArticle, let article = item.article {
            let nounOnly = normalize(item.displayNoun)
            let compactNoun = compactKey(item.displayNoun)
            if answerKey == nounOnly || compactAnswer == compactNoun {
                return .partial(missingArticle: article)
            }
        }

        return .full
    }

    /// Lowercased, trimmed, letters/numbers/spaces only (no Unicode-property regex).
    static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var scalars: [Character] = []
        var lastWasSpace = false

        for character in trimmed.lowercased() {
            if character.isLetter || character.isNumber {
                scalars.append(character)
                lastWasSpace = false
            } else if character.isWhitespace || character == "'" || character == "’" {
                if !lastWasSpace && !scalars.isEmpty {
                    scalars.append(" ")
                    lastWasSpace = true
                }
            }
            // Drop punctuation like ? ! . ,
        }

        while scalars.last == " " {
            scalars.removeLast()
        }

        return String(scalars)
    }

    /// Same as normalize but without spaces ("die Frau" → "diefrau").
    static func compactKey(_ value: String) -> String {
        normalize(value).replacingOccurrences(of: " ", with: "")
    }

    /// Public list used to bias handwriting recognition toward valid answers.
    static func acceptedAnswersForRecognition(prompt: ClozePrompt, item: StudyItem) -> [String] {
        acceptedAnswers(prompt: prompt, item: item)
    }

    private static func acceptedAnswers(prompt: ClozePrompt, item: StudyItem) -> [String] {
        var answers = [
            prompt.expected,
            item.lemma,
            item.displayNoun,
            item.headwordWithArticle,
        ]

        if let article = item.article {
            answers.append("\(article) \(item.displayNoun)")
            answers.append("\(capitalizeFirst(article)) \(item.displayNoun)")
        }

        answers.append(capitalizeFirst(prompt.expected))
        answers.append(prompt.expected.lowercased())

        return Array(Set(answers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
    }

    private static func blankCandidates(for item: StudyItem) -> [String] {
        var values: [String] = []

        if let article = item.article {
            let noun = item.displayNoun
            values.append(contentsOf: [
                "\(article) \(noun)",
                "\(capitalizeFirst(article)) \(noun)",
                noun,
                capitalizeFirst(noun),
            ])
        }

        values.append(item.lemma)
        values.append(item.displayNoun)
        values.append(item.headwordWithArticle)
        values.append(contentsOf: values.map { capitalizeFirst($0) })

        return Array(Set(values.filter { !$0.isEmpty }))
    }

    private static func capitalizeFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }

    private static func spanIncludesArticle(_ span: String) -> Bool {
        let parts = span
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { normalize(String($0)) }
        guard let first = parts.first else { return false }
        return ["der", "die", "das"].contains(first) && parts.count >= 2
    }

    private static func firstMatch(of target: String, in source: String) -> (text: String, range: Range<String.Index>)? {
        guard !target.isEmpty else { return nil }
        guard let range = source.range(
            of: target,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return nil
        }

        if isEmbeddedWordMatch(range: range, in: source) {
            return nil
        }

        return (String(source[range]), range)
    }

    private static func isEmbeddedWordMatch(range: Range<String.Index>, in source: String) -> Bool {
        if range.lowerBound > source.startIndex {
            let before = source[source.index(before: range.lowerBound)]
            if before.isLetter {
                return true
            }
        }

        if range.upperBound < source.endIndex {
            let after = source[range.upperBound]
            if after.isLetter {
                return true
            }
        }

        return false
    }
}
