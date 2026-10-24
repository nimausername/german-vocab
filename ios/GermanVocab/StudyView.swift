import PencilKit
import SwiftUI

private enum StudyStage: Int {
    case writeWord = 0
    case writeCloze = 1
    case rate = 2

    var title: String {
        switch self {
        case .writeWord: return "Write the word"
        case .writeCloze: return "Write the sentence"
        case .rate: return "Rate this card"
        }
    }
}

struct StudyView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [StudyItem]
    @State private var initialCount: Int
    @State private var stage: StudyStage = .writeWord

    @StateObject private var wordCanvas = PencilCanvasStore()
    @StateObject private var clozeCanvas = PencilCanvasStore()
    @State private var clozePrompt: ClozePrompt?

    @State private var recognizedWord = ""
    @State private var recognizedCloze = ""
    @State private var wordResult: ClozeResult?
    @State private var clozeResult: ClozeResult?
    @State private var wordChecked = false
    @State private var clozeChecked = false
    @State private var failedProduction = false
    @State private var isRecognizing = false
    @State private var typedAnswer = ""
    @State private var showTypeFallback = false

    @State private var startedAt = Date()
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    init(initialQueue: [StudyItem]) {
        _queue = State(initialValue: initialQueue)
        _initialCount = State(initialValue: max(initialQueue.count, 1))
    }

    private var completed: Int {
        max(0, initialCount - queue.count)
    }

    private var progress: Double {
        Double(completed) / Double(initialCount)
    }

    var body: some View {
        Group {
            if let current = queue.first {
                activeSession(current)
            } else {
                sessionComplete
            }
        }
        .navigationTitle("Study")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !queue.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(queue.count) left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(queue.count) cards left")
                }
            }
        }
        .animation(.snappy, value: stage)
        .animation(.snappy, value: queue.first?.cardId)
    }

    private func activeSession(_ current: StudyItem) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                ProgressView(value: progress) {
                    Text(stage.title)
                } currentValueLabel: {
                    Text("\(completed) of \(initialCount)")
                        .monospacedDigit()
                }
                .font(.subheadline)

                Group {
                    switch stage {
                    case .writeWord:
                        writeWordStage(current)
                    case .writeCloze:
                        writeClozeStage(current)
                    case .rate:
                        rateStage(current)
                    }
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(for: current)
        }
    }

    // MARK: - Stage 1: Write the word

    private func writeWordStage(_ current: StudyItem) -> some View {
        VStack(spacing: 16) {
            Label(
                current.isNew ? "New" : "Review",
                systemImage: current.isNew ? "sparkles" : "arrow.clockwise"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(current.glossEn)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(
                current.article == nil
                    ? "Write the German word with Apple Pencil"
                    : "Write article + word (e.g. die Frau)"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            WritingPad(
                store: wordCanvas,
                isEnabled: !wordChecked && !isRecognizing,
                prompt: "Writing pad"
            )

            if showTypeFallback && !wordChecked {
                typeFallbackField(hint: "Type article + word") {
                    Task { await checkWordWriting(for: current) }
                }
            }

            if wordChecked {
                resultBlock(
                    recognized: recognizedWord,
                    expected: current.headwordWithArticle,
                    result: wordResult
                )
                headword(current)
            }
        }
    }

    // MARK: - Stage 2: Write in sentence

    private func writeClozeStage(_ current: StudyItem) -> some View {
        let prompt = clozePrompt ?? ClozeSupport.makePrompt(for: current)

        return VStack(spacing: 16) {
            Text("Write what fits the blank")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(prompt.blankedSentence)
                .font(.title2)
                .multilineTextAlignment(.center)

            Text(current.exampleEn)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            WritingPad(
                store: clozeCanvas,
                isEnabled: !clozeChecked && !isRecognizing,
                prompt: "Writing pad"
            )

            if showTypeFallback && !clozeChecked {
                typeFallbackField(hint: prompt.inputHint) {
                    Task { await checkClozeWriting(for: current) }
                }
            }

            if clozeChecked {
                resultBlock(
                    recognized: recognizedCloze,
                    expected: prompt.expected,
                    result: clozeResult
                )
            }
        }
        .task(id: current.cardId) {
            if clozePrompt == nil {
                clozePrompt = ClozeSupport.makePrompt(for: current)
            }
        }
    }

    private func typeFallbackField(hint: String, onSubmit: @escaping () -> Void) -> some View {
        TextField(hint, text: $typedAnswer)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(onSubmit)
            .accessibilityLabel(hint)
    }

    // MARK: - Stage 3: Rate

    private func rateStage(_ current: StudyItem) -> some View {
        VStack(spacing: 16) {
            Label(
                current.isNew ? "New" : "Review",
                systemImage: current.isNew ? "sparkles" : "arrow.clockwise"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            headword(current)

            Text(current.glossEn)
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text(current.exampleDe)
                    .font(.body.italic())
                    .multilineTextAlignment(.center)
                Text(current.exampleEn)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if failedProduction {
                Label("Writing was off — consider Again or Hard", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func headword(_ current: StudyItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let article = current.article {
                Text(article)
                    .foregroundStyle(AppTheme.genderColor(for: article))
            }
            Text(current.displayNoun)
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.65)
                .lineLimit(2)
        }
        .font(.system(size: 44, weight: .medium, design: .serif))
        .frame(maxWidth: .infinity)
        .accessibilityLabel(current.headwordWithArticle)
    }

    @ViewBuilder
    private func resultBlock(recognized: String, expected: String, result: ClozeResult?) -> some View {
        VStack(spacing: 8) {
            Text("Read as: \(recognized.isEmpty ? "—" : recognized)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch result {
            case .full:
                Label("Correct — \(expected)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .partial(let missingArticle):
                Label("Almost — include “\(missingArticle)”", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case .wrong, .none:
                Label("Expected: \(expected)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.headline)
        .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    @ViewBuilder
    private func bottomBar(for current: StudyItem) -> some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            switch stage {
            case .writeWord:
                if wordChecked {
                    prominentButton("Continue to sentence") {
                        clozePrompt = ClozeSupport.makePrompt(for: current)
                        clozeCanvas.clear()
                        withAnimation(.snappy) { stage = .writeCloze }
                    }
                } else {
                    checkControls(
                        title: showTypeFallback && !typedAnswer.isEmpty ? "Check typed answer" : "Check writing",
                        canCheck: wordCanvas.hasStrokes || !typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task { await checkWordWriting(for: current) }
                    }
                }

            case .writeCloze:
                if clozeChecked {
                    prominentButton("Continue") {
                        withAnimation(.snappy) { stage = .rate }
                    }
                } else {
                    checkControls(
                        title: showTypeFallback && !typedAnswer.isEmpty ? "Check typed answer" : "Check writing",
                        canCheck: clozeCanvas.hasStrokes || !typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task { await checkClozeWriting(for: current) }
                    }
                }

            case .rate:
                ratingRow(for: current)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func prominentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: 420)
    }

    private func checkControls(
        title: String,
        canCheck: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Group {
                    if isRecognizing {
                        ProgressView()
                    } else {
                        Text(title)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: 420)
            .disabled(isRecognizing || !canCheck)

            Button(showTypeFallback ? "Hide keyboard" : "Type instead") {
                withAnimation(.snappy) {
                    showTypeFallback.toggle()
                    if !showTypeFallback { typedAnswer = "" }
                }
            }
            .buttonStyle(.borderless)
            .disabled(isRecognizing)
        }
    }

    private func checkWordWriting(for current: StudyItem) async {
        errorMessage = nil
        isRecognizing = true
        defer { isRecognizing = false }

        let prompt = ClozePrompt(
            blankedSentence: "",
            expected: current.headwordWithArticle,
            requiresArticle: current.article != nil,
            inputHint: ""
        )
        let expected = ClozeSupport.acceptedAnswersForRecognition(prompt: prompt, item: current)

        do {
            let recognition = try await recognitionResult(
                drawing: wordCanvas.liveDrawing,
                typed: typedAnswer,
                expected: expected
            )
            applyWordResult(recognition, prompt: prompt, item: current)
        } catch {
            errorMessage = error.localizedDescription
            withAnimation(.snappy) { showTypeFallback = true }
        }
    }

    private func checkClozeWriting(for current: StudyItem) async {
        errorMessage = nil
        isRecognizing = true
        defer { isRecognizing = false }

        let prompt = clozePrompt ?? ClozeSupport.makePrompt(for: current)
        clozePrompt = prompt
        let expected = ClozeSupport.acceptedAnswersForRecognition(prompt: prompt, item: current)

        do {
            let recognition = try await recognitionResult(
                drawing: clozeCanvas.liveDrawing,
                typed: typedAnswer,
                expected: expected
            )
            applyClozeResult(recognition, prompt: prompt, item: current)
        } catch {
            errorMessage = error.localizedDescription
            withAnimation(.snappy) { showTypeFallback = true }
        }
    }

    private func recognitionResult(
        drawing: PKDrawing,
        typed: String,
        expected: [String]
    ) async throws -> HandwritingRecognition {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if showTypeFallback, !trimmed.isEmpty {
            return HandwritingRecognizer.resolveTyped(trimmed, expectedAnswers: expected)
        }
        return try await HandwritingRecognizer.recognizeGerman(
            from: drawing,
            expectedAnswers: expected
        )
    }

    private func applyWordResult(
        _ recognition: HandwritingRecognition,
        prompt: ClozePrompt,
        item: StudyItem
    ) {
        recognizedWord = recognition.matchedExpected
            ? "\(recognition.rawText) → \(recognition.resolvedText)"
            : recognition.rawText
        let result = ClozeSupport.evaluate(
            answer: recognition.resolvedText,
            prompt: prompt,
            item: item
        )
        wordResult = result
        wordChecked = true
        if result != .full {
            failedProduction = true
        }
    }

    private func applyClozeResult(
        _ recognition: HandwritingRecognition,
        prompt: ClozePrompt,
        item: StudyItem
    ) {
        recognizedCloze = recognition.matchedExpected
            ? "\(recognition.rawText) → \(recognition.resolvedText)"
            : recognition.rawText
        let result = ClozeSupport.evaluate(
            answer: recognition.resolvedText,
            prompt: prompt,
            item: item
        )
        clozeResult = result
        clozeChecked = true
        if result != .full {
            failedProduction = true
        }
    }

    private var sessionComplete: some View {
        ContentUnavailableView(
            "Session complete",
            systemImage: "checkmark.circle",
            description: Text("Great work. Come back tomorrow for the next set.")
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: 420)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private func ratingRow(for item: StudyItem) -> some View {
        HStack(spacing: 8) {
            ratingButton("Again", tint: .red, rating: .again, item: item)
            ratingButton("Hard", tint: .orange, rating: .hard, item: item)
            ratingButton("Good", tint: .blue, rating: .good, item: item)
            ratingButton("Easy", tint: .green, rating: .easy, item: item)
        }
        .disabled(isSubmitting)
    }

    private func ratingButton(
        _ title: String,
        tint: Color,
        rating: Rating,
        item: StudyItem
    ) -> some View {
        Button {
            Task { await submit(rating: rating, item: item) }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(tint)
    }

    private func submit(rating: Rating, item: StudyItem) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let finalRating: Rating = (failedProduction && rating == .easy) ? .good : rating
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        do {
            _ = try await session.submitReview(
                cardId: item.cardId,
                rating: finalRating,
                durationMs: durationMs
            )
            if !queue.isEmpty {
                queue.removeFirst()
            }
            resetCardState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetCardState() {
        stage = .writeWord
        wordCanvas.clear()
        clozeCanvas.clear()
        clozePrompt = nil
        recognizedWord = ""
        recognizedCloze = ""
        wordResult = nil
        clozeResult = nil
        wordChecked = false
        clozeChecked = false
        failedProduction = false
        isRecognizing = false
        typedAnswer = ""
        showTypeFallback = false
        startedAt = Date()
        errorMessage = nil
    }
}
