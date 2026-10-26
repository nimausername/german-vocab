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
    /// Content is right; one or more letters use the wrong case.
    case caseMismatch(expected: String)
    case wrong

    var allowsContinue: Bool {
        switch self {
        case .full, .caseMismatch:
            return true
        case .partial, .wrong:
            return false
        }
    }
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

        let candidates = acceptedAnswers(prompt: prompt, item: item) + practiceSentences(for: item)
        if let matched = firstContentMatch(answer: answer, candidates: candidates) {
            return casingResult(answer: answer, expected: matched)
        }

        if prompt.requiresArticle, let article = item.article {
            let nounOnly = normalize(item.displayNoun)
            let compactNoun = compactKey(item.displayNoun)
            if answerKey == nounOnly || compactKey(answer) == compactNoun {
                return .partial(missingArticle: article)
            }
        }

        return .wrong
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

    /// The sentence with the target word removed.
    ///
    /// Uses the server blank when the plan sent one. Otherwise blanks the noun
    /// inside the practice sentence on device.
    static func blankPrompt(for item: StudyItem) -> ClozePrompt {
        let providedBlank = item.blankDe.trimmingCharacters(in: .whitespacesAndNewlines)
        let providedAnswer = item.blankAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if providedBlank.contains("_____"), !providedAnswer.isEmpty {
            return makeBlankPrompt(blanked: providedBlank, expected: providedAnswer)
        }

        let sentence = SentencePractice.resolve(item).german
        if let prompt = blanked(sentence, target: item.displayNoun) {
            return prompt
        }
        if item.lemma != item.displayNoun, let prompt = blanked(sentence, target: item.lemma) {
            return prompt
        }
        return makeBlankPrompt(blanked: "_____", expected: item.headwordWithArticle)
    }

    /// Grades the missing word. The citation form, the sentence form, and the
    /// full practice sentence all pass when the content is right.
    static func evaluateBlank(answer: String, expected: String, item: StudyItem) -> ClozeResult {
        let answerKey = normalize(answer)
        guard !answerKey.isEmpty else { return .wrong }

        var candidates = [
            expected,
            item.headwordWithArticle,
            item.lemma,
            item.blankAnswer,
        ]
        candidates.append(contentsOf: practiceSentences(for: item))

        if let matched = firstContentMatch(answer: answer, candidates: candidates) {
            return casingResult(answer: answer, expected: matched)
        }

        if matches(answer, item.displayNoun) {
            if let article = leadingArticle(in: expected) ?? item.article,
               spanIncludesArticle(expected) || item.article != nil {
                return .partial(missingArticle: article)
            }
            return casingResult(answer: answer, expected: item.displayNoun)
        }

        return .wrong
    }

    /// Grades a full sentence. The bare word is not enough.
    static func evaluateSentence(answer: String, expected: String) -> ClozeResult {
        guard !normalize(answer).isEmpty else { return .wrong }
        guard contentMatches(answer, expected) else { return .wrong }
        return casingResult(answer: answer, expected: expected)
    }

    /// Public list used to bias handwriting recognition toward valid answers.
    static func acceptedAnswersForRecognition(prompt: ClozePrompt, item: StudyItem) -> [String] {
        acceptedAnswers(prompt: prompt, item: item) + practiceSentences(for: item)
    }

    // MARK: - Matching

    /// True when letters/numbers match ignoring case and punctuation.
    static func contentMatches(_ answer: String, _ expected: String) -> Bool {
        let trimmed = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return normalize(answer) == normalize(trimmed) || compactKey(answer) == compactKey(trimmed)
    }

    /// Letter casing must match the expected form once content already matches.
    static func casingMatches(_ answer: String, _ expected: String) -> Bool {
        let answerLetters = letters(in: answer)
        let expectedLetters = letters(in: expected)
        guard answerLetters.count == expectedLetters.count, !expectedLetters.isEmpty else {
            return true
        }
        return answerLetters.elementsEqual(expectedLetters)
    }

    static func casingResult(answer: String, expected: String) -> ClozeResult {
        let trimmed = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        if casingMatches(answer, trimmed) {
            return .full
        }
        return .caseMismatch(expected: trimmed)
    }

    private static func letters(in value: String) -> [Character] {
        value.filter(\.isLetter)
    }

    private static func firstContentMatch(answer: String, candidates: [String]) -> String? {
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, contentMatches(answer, trimmed) else { continue }
            return trimmed
        }
        return nil
    }

    private static func practiceSentences(for item: StudyItem) -> [String] {
        var sentences: [String] = []
        let practice = item.practiceDe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !practice.isEmpty {
            sentences.append(practice)
        }
        let example = item.exampleDe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !example.isEmpty, example != practice {
            sentences.append(example)
        }
        let resolved = SentencePractice.resolve(item).german.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty, !sentences.contains(resolved) {
            sentences.append(resolved)
        }
        return sentences
    }

    private static func acceptedAnswers(prompt: ClozePrompt, item: StudyItem) -> [String] {
        var answers = [
            prompt.expected,
            item.lemma,
            item.displayNoun,
            item.headwordWithArticle,
            item.blankAnswer,
        ]

        if let article = item.article {
            answers.append("\(article) \(item.displayNoun)")
            answers.append("\(capitalizeFirst(article)) \(item.displayNoun)")
        }

        answers.append(capitalizeFirst(prompt.expected))

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

    private static let leadingArticles: Set<String> = [
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "einer", "eines",
        "kein", "keine", "keinen", "keinem", "keiner",
    ]

    private static func matches(_ answer: String, _ expected: String) -> Bool {
        contentMatches(answer, expected)
    }

    private static func makeBlankPrompt(blanked: String, expected: String) -> ClozePrompt {
        let requiresArticle = spanIncludesArticle(expected)
        return ClozePrompt(
            blankedSentence: blanked,
            expected: expected,
            requiresArticle: requiresArticle,
            inputHint: requiresArticle
                ? "Type the missing word and its article"
                : "Type the missing word"
        )
    }

    private static func blanked(_ sentence: String, target: String) -> ClozePrompt? {
        guard let match = firstMatch(of: target, in: sentence) else { return nil }
        let expanded = includingLeadingArticle(range: match.range, in: sentence)
        let blankedSentence = sentence.replacingCharacters(in: expanded.range, with: "_____")
        let expected = expanded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else { return nil }
        return makeBlankPrompt(blanked: blankedSentence, expected: expected)
    }

    private static func includingLeadingArticle(
        range: Range<String.Index>,
        in source: String
    ) -> (text: String, range: Range<String.Index>) {
        let prefix = source[..<range.lowerBound]
        guard let articleRange = prefix.range(
            of: #"(?i)(?:der|die|das|den|dem|des|ein|eine|einen|einem|einer|eines|kein|keine|keinen)\s+$"#,
            options: .regularExpression
        ) else {
            return (String(source[range]), range)
        }
        let expanded = articleRange.lowerBound..<range.upperBound
        return (String(source[expanded]), expanded)
    }

    private static func leadingArticle(in span: String) -> String? {
        let parts = span.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let article = normalize(String(parts[0]))
        return leadingArticles.contains(article) ? article : nil
    }

    private static func spanIncludesArticle(_ span: String) -> Bool {
        leadingArticle(in: span) != nil
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
