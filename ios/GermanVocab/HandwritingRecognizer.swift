import PencilKit
import UIKit
import Vision

struct HandwritingRecognition {
    /// Top raw reading (for display).
    let rawText: String
    /// Best interpretation after matching against expected answers (if any).
    let resolvedText: String
    /// True when resolvedText was snapped to an expected answer via fuzzy/OCR-aware match.
    let matchedExpected: Bool
}

enum HandwritingRecognizer {
    enum RecognizerError: LocalizedError {
        case emptyDrawing
        case noTextFound
        case vision(String)

        var errorDescription: String? {
            switch self {
            case .emptyDrawing:
                return "Write something first."
            case .noTextFound:
                return "Couldn’t read the handwriting. Try again more clearly, or type the answer."
            case .vision(let message):
                return message
            }
        }
    }

    /// Pairs Vision often swaps in Latin handwriting (f ↔ r is the main German issue).
    private static let confusionPairs: Set<String> = [
        "fr", "rf",
        "rn", "nr",
        "nm", "mn",
        "il", "li",
        "o0", "0o",
        "sz", "zs", "sß", "ßs",
        "aä", "äa",
        "oö", "öo",
        "uü", "üu",
    ]

    /**
     Recognizes German handwriting and biases toward `expectedAnswers`
     so OCR mistakes like f→r still accept a clearly intended word.
     */
    static func recognizeGerman(
        from drawing: PKDrawing,
        expectedAnswers: [String] = []
    ) async throws -> HandwritingRecognition {
        guard !drawing.strokes.isEmpty else { throw RecognizerError.emptyDrawing }

        var candidates: [String] = []

        if #available(iOS 27.0, *) {
            candidates.append(contentsOf: await pencilKitCandidates(
                from: drawing,
                expectedAnswers: expectedAnswers
            ))
        }

        if candidates.isEmpty {
            candidates.append(contentsOf: try await visionCandidates(
                from: drawing,
                hints: sanitizedHints(expectedAnswers)
            ))
        }

        guard let bestRaw = candidates.first, !bestRaw.isEmpty else {
            throw RecognizerError.noTextFound
        }

        return resolve(candidates: candidates, bestRaw: bestRaw, expectedAnswers: expectedAnswers)
    }

    /// Grades a typed answer with the same expected-answer bias as handwriting.
    static func resolveTyped(_ text: String, expectedAnswers: [String]) -> HandwritingRecognition {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return resolve(candidates: [trimmed], bestRaw: trimmed, expectedAnswers: expectedAnswers)
    }

    // MARK: - Resolve

    private static func resolve(
        candidates: [String],
        bestRaw: String,
        expectedAnswers: [String]
    ) -> HandwritingRecognition {
        if expectedAnswers.isEmpty {
            return HandwritingRecognition(
                rawText: bestRaw,
                resolvedText: bestRaw,
                matchedExpected: false
            )
        }

        for candidate in candidates {
            if let exact = firstExactMatch(candidate, in: expectedAnswers) {
                return HandwritingRecognition(
                    rawText: bestRaw,
                    resolvedText: exact,
                    matchedExpected: true
                )
            }
        }

        if let ocr = bestOcrConfusionMatch(among: candidates, expectedAnswers: expectedAnswers) {
            return HandwritingRecognition(
                rawText: bestRaw,
                resolvedText: ocr,
                matchedExpected: true
            )
        }

        if let fuzzy = bestFuzzyMatch(among: candidates, expectedAnswers: expectedAnswers) {
            return HandwritingRecognition(
                rawText: bestRaw,
                resolvedText: fuzzy,
                matchedExpected: true
            )
        }

        return HandwritingRecognition(
            rawText: bestRaw,
            resolvedText: bestRaw,
            matchedExpected: false
        )
    }

    // MARK: - PencilKit (iOS 27+)

    @available(iOS 27.0, *)
    private static func pencilKitCandidates(
        from drawing: PKDrawing,
        expectedAnswers: [String]
    ) async -> [String] {
        let recognizer = PKStrokeRecognizer(preferredLanguages: [
            Locale.Language(languageCode: .init("de")),
            Locale.Language(languageCode: .init("en")),
        ])

        var seen = Set<String>()
        var ordered: [String] = []

        func add(_ raw: String?) {
            guard let raw else { return }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let key = ClozeSupport.normalize(text)
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            ordered.append(text)
        }

        // Paper-scale first (what Apple’s recognizer is trained on), then original.
        for variant in paperScaleVariants(drawing) {
            await recognizer.updateDrawing(variant)
            add(await recognizer.recognizedText(strokeIDs: nil))
            add(await recognizer.indexableContent)

            for expected in sanitizedHints(expectedAnswers) {
                let hits = await recognizer.search(
                    expected,
                    fullWordsOnly: false,
                    caseMatchingOnly: false
                )
                if !hits.isEmpty {
                    add(expected)
                }
            }

            if !ordered.isEmpty { break }
        }

        return ordered
    }

    /// Scales large pad writing down to ~handwriting on paper.
    private static func paperScaleVariants(_ drawing: PKDrawing) -> [PKDrawing] {
        let height = drawing.bounds.height
        guard height > 1 else { return [drawing] }

        let targetHeights: [CGFloat] = [40, 56, 72]
        var variants: [PKDrawing] = []
        var seenScales = Set<CGFloat>()

        for target in targetHeights {
            let scale = target / height
            let rounded = (scale * 100).rounded() / 100
            guard rounded > 0.05, rounded < 0.98, !seenScales.contains(rounded) else { continue }
            seenScales.insert(rounded)
            variants.append(drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale)))
        }

        variants.append(drawing)
        return variants
    }

    // MARK: - Vision fallback

    private struct VisionConfig {
        let level: VNRequestTextRecognitionLevel
        let languages: [String]
        let languageCorrection: Bool
        let customWords: [String]
    }

    private static func visionConfigs(hints: [String]) -> [VisionConfig] {
        [
            VisionConfig(level: .accurate, languages: ["de-DE"], languageCorrection: true, customWords: hints),
            VisionConfig(level: .accurate, languages: ["de-DE", "en-US"], languageCorrection: false, customWords: hints),
            VisionConfig(level: .fast, languages: ["de-DE"], languageCorrection: false, customWords: hints),
            VisionConfig(level: .fast, languages: ["en-US"], languageCorrection: false, customWords: hints),
        ]
    }

    private static func sanitizedHints(_ answers: [String]) -> [String] {
        Array(Set(answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
    }

    private static func visionCandidates(from drawing: PKDrawing, hints: [String]) async throws -> [String] {
        let images = try renderForOCR(drawing)
        for image in images {
            for config in visionConfigs(hints: hints) {
                let batch = try await runVision(cgImage: image, config: config)
                if !batch.isEmpty {
                    return batch
                }
            }
        }
        return []
    }

    private static func runVision(cgImage: CGImage, config: VisionConfig) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: RecognizerError.vision(error.localizedDescription))
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var seen = Set<String>()
                var ordered: [String] = []

                for observation in observations {
                    for candidate in observation.topCandidates(10) {
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        let key = ClozeSupport.normalize(text)
                        guard !key.isEmpty, !seen.contains(key) else { continue }
                        seen.insert(key)
                        ordered.append(text)
                    }
                }

                let joinedTop = observations.compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !joinedTop.isEmpty {
                    let key = ClozeSupport.normalize(joinedTop)
                    if !seen.contains(key) {
                        ordered.insert(joinedTop, at: 0)
                    }
                }

                continuation.resume(returning: ordered)
            }

            request.recognitionLevel = config.level
            request.usesLanguageCorrection = config.languageCorrection
            request.recognitionLanguages = config.languages
            request.customWords = config.customWords
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = false
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: RecognizerError.vision(error.localizedDescription))
            }
        }
    }

    /// Fits ink into document-sized white images. Large pad letters break Vision.
    private static func renderForOCR(_ drawing: PKDrawing) throws -> [CGImage] {
        let bounds = drawing.bounds
        guard !bounds.isNull, !bounds.isInfinite, bounds.width >= 2, bounds.height >= 2 else {
            throw RecognizerError.emptyDrawing
        }

        let padded = bounds.insetBy(dx: -24, dy: -24)
        let targets: [CGSize] = [
            CGSize(width: 720, height: 180),
            CGSize(width: 960, height: 240),
        ]

        var images: [CGImage] = []
        for target in targets {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 2
            format.opaque = true

            let renderer = UIGraphicsImageRenderer(size: target, format: format)
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: target))

                let box = CGRect(origin: .zero, size: target).insetBy(dx: 16, dy: 16)
                let fit = aspectFit(padded.size, in: box)
                let ink = drawing.image(from: padded, scale: 2)
                ink.draw(in: fit)
            }

            if let cgImage = image.cgImage {
                images.append(cgImage)
            }
        }

        guard !images.isEmpty else {
            throw RecognizerError.vision("Could not render handwriting.")
        }
        return images
    }

    private static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        let scale = min(box.width / max(size.width, 1), box.height / max(size.height, 1))
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(
            x: box.midX - width / 2,
            y: box.midY - height / 2,
            width: width,
            height: height
        )
    }

    // MARK: - Matching

    private static func firstExactMatch(_ candidate: String, in expectedAnswers: [String]) -> String? {
        let key = ClozeSupport.normalize(candidate)
        let compact = ClozeSupport.compactKey(candidate)
        for expected in expectedAnswers {
            if ClozeSupport.normalize(expected) == key || ClozeSupport.compactKey(expected) == compact {
                return expected
            }
        }
        return nil
    }

    /// Same length only; every mismatch must be a known OCR pair (e.g. f↔r).
    private static func bestOcrConfusionMatch(
        among candidates: [String],
        expectedAnswers: [String]
    ) -> String? {
        var bestExpected: String?
        var bestMismatches = Int.max

        for candidate in candidates {
            let a = Array(ClozeSupport.compactKey(candidate))
            for expected in expectedAnswers {
                let b = Array(ClozeSupport.compactKey(expected))
                guard a.count == b.count, !a.isEmpty else { continue }

                var mismatches = 0
                var ok = true
                for i in a.indices {
                    if a[i] == b[i] { continue }
                    let pair = String([a[i], b[i]])
                    guard confusionPairs.contains(pair) else {
                        ok = false
                        break
                    }
                    mismatches += 1
                }
                guard ok else { continue }

                let maxSwaps = max(1, a.count / 4)
                guard mismatches <= maxSwaps, mismatches < bestMismatches else { continue }
                bestMismatches = mismatches
                bestExpected = expected
            }
        }

        return bestExpected
    }

    private static func bestFuzzyMatch(among candidates: [String], expectedAnswers: [String]) -> String? {
        var bestExpected: String?
        var bestScore = Int.max

        for candidate in candidates {
            let a = ClozeSupport.compactKey(candidate)
            for expected in expectedAnswers {
                let b = ClozeSupport.compactKey(expected)
                let score = levenshtein(a, b)
                let maxAllowed = maxAllowedEdits(for: b)
                if score > 0, score <= maxAllowed, score < bestScore {
                    bestScore = score
                    bestExpected = expected
                }
            }
        }

        return bestExpected
    }

    private static func maxAllowedEdits(for compactExpected: String) -> Int {
        let length = compactExpected.count
        if length <= 4 { return 0 }
        if length <= 8 { return 1 }
        return 2
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count
        if n == 0 { return m }
        if m == 0 { return n }

        var previous = Array(0 ... m)
        var current = Array(repeating: 0, count: m + 1)

        for i in 1 ... n {
            current[0] = i
            for j in 1 ... m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }

        return previous[m]
    }
}
