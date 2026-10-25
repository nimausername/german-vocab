import PencilKit
import SwiftUI

private enum StudyStage: Int {
    case writeWord = 0
    case writeCloze = 1
    case rate = 2

    func title(typing: Bool) -> String {
        switch self {
        case .writeWord: return typing ? "Type the word" : "Write the word"
        case .writeCloze: return typing ? "Type the sentence" : "Write the sentence"
        case .rate: return "Rate this card"
        }
    }
}

struct StudyView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
    @FocusState private var typingFocused: Bool

    /// iPhone has no Apple Pencil, so production is typed.
    private var typingIsPrimary: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var showsTypingField: Bool {
        typingIsPrimary || showTypeFallback
    }

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
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            if !queue.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(queue.count) left")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(queue.count) cards left")
                }
            }
        }
        .animation(AppMotion.step, value: stage)
        .animation(AppMotion.step, value: queue.first?.cardId)
    }

    private func activeSession(_ current: StudyItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress) {
                        Text("Session")
                    } currentValueLabel: {
                        Text("\(completed) of \(initialCount)")
                            .monospacedDigit()
                    }
                    .font(.subheadline)

                    stageTrack
                }

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
                .id(stage)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(trigger: wordChecked) { old, new in
            guard new, !old else { return nil }
            return feedback(for: wordResult)
        }
        .sensoryFeedback(trigger: clozeChecked) { old, new in
            guard new, !old else { return nil }
            return feedback(for: clozeResult)
        }
        .sensoryFeedback(.selection, trigger: queue.count) { old, new in
            new < old
        }
        .safeAreaBar(edge: .bottom) {
            bottomBar(for: current)
        }
    }

    private var stageTrack: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= stage.rawValue ? AppTheme.accent : Color.primary.opacity(0.12))
                        .frame(height: 5)
                }
            }
            .animation(AppMotion.step, value: stage)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(stage.rawValue + 1) of 3")
            .accessibilityValue(stage.title(typing: typingIsPrimary))

            Text(stage.title(typing: typingIsPrimary))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func feedback(for result: ClozeResult?) -> SensoryFeedback {
        switch result {
        case .full:
            return .success
        case .partial:
            return .warning
        case .wrong, .none:
            return .error
        }
    }

    // MARK: - Stage 1: Write the word

    private func writeWordStage(_ current: StudyItem) -> some View {
        VStack(spacing: 16) {
            kindLabel(current)

            Text(current.glossEn)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(wordPrompt(for: current))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !typingIsPrimary {
                WritingPad(
                    store: wordCanvas,
                    isEnabled: !wordChecked && !isRecognizing,
                    prompt: "Writing pad"
                )
            }

            if showsTypingField && !wordChecked {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
                headword(current)
            }
        }
        .animation(AppMotion.reveal, value: wordChecked)
    }

    // MARK: - Stage 2: Write in sentence

    private func writeClozeStage(_ current: StudyItem) -> some View {
        let prompt = clozePrompt ?? ClozeSupport.makePrompt(for: current)

        return VStack(spacing: 16) {
            Text(typingIsPrimary ? "Type what fits the blank" : "Write what fits the blank")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(prompt.blankedSentence)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(current.exampleEn)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !typingIsPrimary {
                WritingPad(
                    store: clozeCanvas,
                    isEnabled: !clozeChecked && !isRecognizing,
                    prompt: "Writing pad"
                )
            }

            if showsTypingField && !clozeChecked {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(AppMotion.reveal, value: clozeChecked)
        .task(id: current.cardId) {
            if clozePrompt == nil {
                clozePrompt = ClozeSupport.makePrompt(for: current)
            }
        }
    }

    private func typeFallbackField(hint: String, onSubmit: @escaping () -> Void) -> some View {
        TextField(hint, text: $typedAnswer)
            .font(.title3)
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($typingFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            }
            .onSubmit(onSubmit)
            .onAppear {
                if typingIsPrimary {
                    typingFocused = true
                }
            }
            .accessibilityLabel(hint)
    }

    private func wordPrompt(for current: StudyItem) -> String {
        if typingIsPrimary {
            return current.article == nil
                ? "Type the German word"
                : "Type article + word (e.g. die Frau)"
        }
        return current.article == nil
            ? "Write the German word with Apple Pencil"
            : "Write article + word (e.g. die Frau)"
    }

    // MARK: - Stage 3: Rate

    private func rateStage(_ current: StudyItem) -> some View {
        VStack(spacing: 16) {
            kindLabel(current)
            headword(current)

            Text(current.glossEn)
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text(current.exampleDe)
                    .font(.body.italic())
                Text(current.exampleEn)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if failedProduction {
                Label(
                    typingIsPrimary
                        ? "Answer was off — consider Again or Hard"
                        : "Writing was off — consider Again or Hard",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            }
        }
    }

    private func kindLabel(_ current: StudyItem) -> some View {
        StatusChip(
            title: current.isNew ? "New" : "Review",
            tint: current.isNew ? AppTheme.accent : .secondary,
            systemImage: current.isNew ? "sparkles" : "arrow.clockwise"
        )
    }

    private func headword(_ current: StudyItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ArticleText(article: current.article, prominent: true)
            Text(current.displayNoun)
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.65)
                .lineLimit(2)
        }
        .font(.system(size: 44, weight: .medium, design: .serif))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(current.headwordWithArticle)
    }

    @ViewBuilder
    private func resultBlock(recognized: String, expected: String, result: ClozeResult?) -> some View {
        let tint = resultTint(result)
        VStack(spacing: 8) {
            Text("Read as: \(recognized.isEmpty ? "—" : recognized)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch result {
            case .full:
                Label("Correct — \(expected)", systemImage: "checkmark.circle.fill")
            case .partial(let missingArticle):
                Label("Almost — include “\(missingArticle)”", systemImage: "exclamationmark.circle.fill")
            case .wrong, .none:
                Label("Expected: \(expected)", systemImage: "xmark.circle.fill")
            }
        }
        .font(.headline)
        .foregroundStyle(tint)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func resultTint(_ result: ClozeResult?) -> Color {
        switch result {
        case .full:
            return .green
        case .partial:
            return .orange
        case .wrong, .none:
            return .red
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func bottomBar(for current: StudyItem) -> some View {
        BottomActionBar {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .actionColumn()
            }

            if isSubmitting {
                ProgressView("Saving")
            }

            switch stage {
            case .writeWord:
                if wordChecked {
                    prominentButton("Continue to Sentence") {
                        clozePrompt = ClozeSupport.makePrompt(for: current)
                        clozeCanvas.clear()
                        withAnimation(AppMotion.step) { stage = .writeCloze }
                    }
                } else {
                    checkControls(
                        title: checkTitle,
                        canCheck: canCheckAnswer(hasStrokes: wordCanvas.hasStrokes)
                    ) {
                        Task { await checkWordWriting(for: current) }
                    }
                }

            case .writeCloze:
                if clozeChecked {
                    prominentButton("Continue") {
                        withAnimation(AppMotion.step) { stage = .rate }
                    }
                } else {
                    checkControls(
                        title: checkTitle,
                        canCheck: canCheckAnswer(hasStrokes: clozeCanvas.hasStrokes)
                    ) {
                        Task { await checkClozeWriting(for: current) }
                    }
                }

            case .rate:
                ratingRow(for: current)
            }
        }
    }

    private func prominentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .prominentGlassCapsule()
        .actionColumn()
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
            .prominentGlassCapsule()
            .actionColumn()
            .disabled(isRecognizing || !canCheck)

            if !typingIsPrimary {
                Button(showTypeFallback ? "Hide Keyboard" : "Type Instead", systemImage: "keyboard") {
                    withAnimation(AppMotion.step) {
                        showTypeFallback.toggle()
                        if !showTypeFallback { typedAnswer = "" }
                    }
                }
                .glassCapsule(size: .small)
                .disabled(isRecognizing)
                .sensoryFeedback(.selection, trigger: showTypeFallback)
            }
        }
    }

    private var checkTitle: String {
        if typingIsPrimary || (showTypeFallback && !typedAnswer.isEmpty) {
            return "Check Typed Answer"
        }
        return "Check Writing"
    }

    private func canCheckAnswer(hasStrokes: Bool) -> Bool {
        let typed = !typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if typingIsPrimary {
            return typed
        }
        return hasStrokes || typed
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
            withAnimation(AppMotion.step) { showTypeFallback = true }
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
            withAnimation(AppMotion.step) { showTypeFallback = true }
        }
    }

    private func recognitionResult(
        drawing: PKDrawing,
        typed: String,
        expected: [String]
    ) async throws -> HandwritingRecognition {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if (typingIsPrimary || showTypeFallback), !trimmed.isEmpty {
            return HandwritingRecognizer.resolveTyped(trimmed)
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
        ContentUnavailableView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: initialCount)
                Text("Session complete")
                    .font(.title2.bold())
            }
        } description: {
            Text("Great work. Come back tomorrow for the next set.")
        }
        .safeAreaBar(edge: .bottom) {
            BottomActionBar {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .prominentGlassCapsule()
                .actionColumn()
            }
        }
    }

    private func ratingRow(for item: StudyItem) -> some View {
        GlassEffectContainer(spacing: 10) {
            Group {
                if horizontalSizeClass == .compact {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            ratingButton("Again", tint: .red, rating: .again, item: item)
                            ratingButton("Hard", tint: .orange, rating: .hard, item: item)
                        }
                        HStack(spacing: 10) {
                            ratingButton("Good", tint: .blue, rating: .good, item: item)
                            ratingButton("Easy", tint: .green, rating: .easy, item: item)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        ratingButton("Again", tint: .red, rating: .again, item: item)
                        ratingButton("Hard", tint: .orange, rating: .hard, item: item)
                        ratingButton("Good", tint: .blue, rating: .good, item: item)
                        ratingButton("Easy", tint: .green, rating: .easy, item: item)
                    }
                }
            }
            .actionColumn()
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
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .glassCapsule()
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
