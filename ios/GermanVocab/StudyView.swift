import PencilKit
import SwiftUI

private enum StudyStage: Int {
    case situation = 0
    case writeWord = 1
    case writeBlank = 2
    case rate = 3

    func title(typing: Bool, revealed: Bool) -> String {
        switch self {
        case .situation:
            return revealed ? "New word" : "Read the sentence"
        case .writeWord:
            return typing ? "Type the word" : "Write the word"
        case .writeBlank:
            return typing ? "Type the missing word" : "Write the missing word"
        case .rate:
            return "Rate this card"
        }
    }
}

private func openingStage(for item: StudyItem?) -> StudyStage {
    guard let item else { return .writeBlank }
    if item.isNew { return .situation }
    if item.recallWord { return .writeWord }
    return .writeBlank
}

struct StudyView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [StudyItem]
    @State private var initialCount: Int
    @State private var stage: StudyStage
    @State private var meaningRevealed: Bool

    @StateObject private var wordCanvas = PencilCanvasStore()
    @StateObject private var blankCanvas = PencilCanvasStore()
    @StateObject private var speaker = GermanSpeaker()

    @State private var recognizedWord = ""
    @State private var recognizedBlank = ""
    @State private var wordResult: ClozeResult?
    @State private var blankResult: ClozeResult?
    @State private var wordChecked = false
    @State private var blankChecked = false
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
        _stage = State(initialValue: openingStage(for: initialQueue.first))
        _meaningRevealed = State(initialValue: false)
    }

    private var completed: Int {
        max(0, initialCount - queue.count)
    }

    private var progress: Double {
        Double(completed) / Double(initialCount)
    }

    private var introSpeechID: String {
        "\(queue.first?.cardId ?? "")-\(stage.rawValue)-\(meaningRevealed)"
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
        .onAppear { speaker.refresh() }
        .onDisappear { speaker.stop() }
        .task(id: introSpeechID) {
            guard stage == .situation, let current = queue.first else { return }
            let sentence = SentencePractice.resolve(current)
            speaker.speak(meaningRevealed ? current.headwordWithArticle : sentence.german)
        }
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

                    stageTrack(for: current)
                }

                Group {
                    switch stage {
                    case .situation:
                        situationStage(current)
                    case .writeWord:
                        recallWordStage(current)
                    case .writeBlank:
                        blankStage(current)
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
        .sensoryFeedback(trigger: blankChecked) { old, new in
            guard new, !old else { return nil }
            return feedback(for: blankResult)
        }
        .sensoryFeedback(.selection, trigger: queue.count) { old, new in
            new < old
        }
        .safeAreaBar(edge: .bottom) {
            bottomBar(for: current)
        }
    }

    private func stages(for item: StudyItem) -> [StudyStage] {
        var steps: [StudyStage] = []
        if item.isNew {
            steps.append(.situation)
        }
        if item.recallWord {
            steps.append(.writeWord)
        }
        steps.append(.writeBlank)
        steps.append(.rate)
        return steps
    }

    private func stageTrack(for item: StudyItem) -> some View {
        let steps = stages(for: item)
        let currentIndex = steps.firstIndex(of: stage) ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(index <= currentIndex ? AppTheme.accent : Color.primary.opacity(0.12))
                        .frame(height: 5)
                }
            }
            .animation(AppMotion.step, value: stage)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(currentIndex + 1) of \(steps.count)")
            .accessibilityValue(stage.title(typing: typingIsPrimary, revealed: meaningRevealed))

            Text(stage.title(typing: typingIsPrimary, revealed: meaningRevealed))
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

    // MARK: - Situation

    private func situationStage(_ current: StudyItem) -> some View {
        let sentence = SentencePractice.resolve(current)
        return VStack(spacing: 16) {
            kindLabel(current)

            if meaningRevealed {
                headword(current)
                speakRow(text: current.headwordWithArticle, prominent: false)

                Text(sentence.german)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(sentence.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Next you write the word, then fill it into this sentence.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                voiceNote()
            } else {
                Text(sentence.german)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                speakRow(text: sentence.german, prominent: false)

                Text("What does this say?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                voiceNote()
            }
        }
    }

    // MARK: - Write the word

    private func recallWordStage(_ current: StudyItem) -> some View {
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
                if speaker.premiumAvailable {
                    speakRow(text: current.headwordWithArticle, prominent: false)
                }
            }
        }
        .animation(AppMotion.reveal, value: wordChecked)
    }

    // MARK: - Blank

    private func blankStage(_ current: StudyItem) -> some View {
        let sentence = SentencePractice.resolve(current)
        let prompt = ClozeSupport.blankPrompt(for: current)

        return VStack(spacing: 16) {
            Text(sentence.english)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(prompt.blankedSentence)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("German sentence with a missing word")

            Text(blankPrompt(for: prompt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !typingIsPrimary {
                WritingPad(
                    store: blankCanvas,
                    isEnabled: !blankChecked && !isRecognizing,
                    prompt: "Writing pad"
                )
            }

            if showsTypingField && !blankChecked {
                typeFallbackField(hint: prompt.inputHint) {
                    Task { await checkBlankWriting(for: current) }
                }
            }

            if blankChecked {
                resultBlock(
                    recognized: recognizedBlank,
                    expected: prompt.expected,
                    result: blankResult
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                if speaker.premiumAvailable {
                    speakRow(text: sentence.german, prominent: false)
                }
            }

            voiceNote()
        }
        .animation(AppMotion.reveal, value: blankChecked)
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

    private func blankPrompt(for prompt: ClozePrompt) -> String {
        if typingIsPrimary {
            return prompt.requiresArticle
                ? "Type the missing word and its article"
                : "Type the missing word"
        }
        return prompt.requiresArticle
            ? "Write the missing word and its article"
            : "Write the missing word"
    }

    // MARK: - Rate

    private func rateStage(_ current: StudyItem) -> some View {
        let sentence = SentencePractice.resolve(current)
        return VStack(spacing: 16) {
            kindLabel(current)
            headword(current)
            speakRow(text: sentence.german, prominent: false)

            Text(current.glossEn)
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text(sentence.german)
                    .font(.body.italic())
                Text(sentence.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            voiceNote()
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
    private func speakRow(text: String, prominent: Bool) -> some View {
        if speaker.premiumAvailable {
            Button {
                speaker.speak(text)
            } label: {
                Label("Play", systemImage: "speaker.wave.2.fill")
            }
            .glassCapsule(size: prominent ? .large : .small)
            .accessibilityLabel("Play German")
            .accessibilityHint("Speaks the German with the Premium voice")
        }
    }

    private func voiceNote() -> some View {
        Group {
            if !speaker.premiumAvailable {
                Text("Download a Premium German voice to hear this. Settings → Accessibility → Spoken Content → Voices → German.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
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
            case .situation:
                if meaningRevealed {
                    prominentButton("Write it") {
                        typedAnswer = ""
                        showTypeFallback = false
                        withAnimation(AppMotion.step) {
                            stage = current.recallWord ? .writeWord : .writeBlank
                        }
                    }
                } else {
                    prominentButton("Show meaning") {
                        withAnimation(AppMotion.step) { meaningRevealed = true }
                    }
                }

            case .writeWord:
                if wordChecked {
                    if wordResult == .full {
                        prominentButton("Continue") {
                            wordCanvas.clear()
                            blankCanvas.clear()
                            typedAnswer = ""
                            showTypeFallback = false
                            withAnimation(AppMotion.step) { stage = .writeBlank }
                        }
                    } else {
                        prominentButton("Next card") {
                            Task { await submit(rating: .again, item: current) }
                        }
                    }
                } else {
                    checkControls(
                        title: checkTitle,
                        canCheck: canCheckAnswer(hasStrokes: wordCanvas.hasStrokes)
                    ) {
                        Task { await checkWordWriting(for: current) }
                    }
                }

            case .writeBlank:
                if blankChecked {
                    if blankResult == .full {
                        prominentButton("Continue") {
                            withAnimation(AppMotion.step) { stage = .rate }
                        }
                    } else {
                        prominentButton("Next card") {
                            Task { await submit(rating: .again, item: current) }
                        }
                    }
                } else {
                    checkControls(
                        title: checkTitle,
                        canCheck: canCheckAnswer(hasStrokes: blankCanvas.hasStrokes)
                    ) {
                        Task { await checkBlankWriting(for: current) }
                    }
                }

            case .rate:
                ratingRow(for: current)
            }
        }
        .disabled(isSubmitting)
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

    private func checkBlankWriting(for current: StudyItem) async {
        errorMessage = nil
        isRecognizing = true
        defer { isRecognizing = false }

        let prompt = ClozeSupport.blankPrompt(for: current)
        let expected = [
            prompt.expected,
            current.headwordWithArticle,
            current.lemma,
            current.displayNoun,
        ]

        do {
            let recognition = try await recognitionResult(
                drawing: blankCanvas.liveDrawing,
                typed: typedAnswer,
                expected: expected
            )
            applyBlankResult(recognition, prompt: prompt, item: current)
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
        speaker.speak(item.headwordWithArticle)
    }

    private func applyBlankResult(
        _ recognition: HandwritingRecognition,
        prompt: ClozePrompt,
        item: StudyItem
    ) {
        recognizedBlank = recognition.matchedExpected
            ? "\(recognition.rawText) → \(recognition.resolvedText)"
            : recognition.rawText
        let result = ClozeSupport.evaluateBlank(
            answer: recognition.resolvedText,
            expected: prompt.expected,
            item: item
        )
        blankResult = result
        blankChecked = true
        speaker.speak(SentencePractice.resolve(item).german)
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
            HStack(spacing: 10) {
                ratingButton("Good", tint: .blue, rating: .good, item: item)
                ratingButton("Easy", tint: .green, rating: .easy, item: item)
            }
            .actionColumn()
        }
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

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        do {
            _ = try await session.submitReview(
                cardId: item.cardId,
                rating: rating,
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
        let next = queue.first
        stage = openingStage(for: next)
        meaningRevealed = false
        wordCanvas.clear()
        blankCanvas.clear()
        recognizedWord = ""
        recognizedBlank = ""
        wordResult = nil
        blankResult = nil
        wordChecked = false
        blankChecked = false
        isRecognizing = false
        typedAnswer = ""
        showTypeFallback = false
        startedAt = Date()
        errorMessage = nil
        speaker.stop()
    }
}
