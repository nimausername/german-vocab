import PencilKit
import SwiftUI

/// Holds a live `PKCanvasView` so recognition always reads the ink on screen.
@MainActor
final class PencilCanvasStore: ObservableObject {
    weak var canvas: PKCanvasView?

    @Published var hasStrokes = false

    var liveDrawing: PKDrawing {
        canvas?.drawing ?? PKDrawing()
    }

    func clear() {
        canvas?.drawing = PKDrawing()
        hasStrokes = false
    }
}

/// PencilKit writing surface for the word and the sentence.
struct PencilCanvasView: UIViewRepresentable {
    @ObservedObject var store: PencilCanvasStore
    var isEnabled: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: UIColor.black, width: 16)
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.becomeFirstResponder()
        canvas.isUserInteractionEnabled = isEnabled
        store.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.store = store
        store.canvas = canvas
        canvas.isUserInteractionEnabled = isEnabled
        canvas.alpha = isEnabled ? 1 : 0.55
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var store: PencilCanvasStore

        init(store: PencilCanvasStore) {
            self.store = store
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let hasInk = !canvasView.drawing.strokes.isEmpty
            DispatchQueue.main.async { [weak self] in
                self?.store.hasStrokes = hasInk
            }
        }
    }
}

struct WritingPad: View {
    @ObservedObject var store: PencilCanvasStore
    var isEnabled: Bool = true
    var prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(prompt, systemImage: "pencil.and.scribble")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear", systemImage: "eraser") {
                    store.clear()
                }
                .labelStyle(.titleAndIcon)
                .glassCapsule(size: .small)
                .disabled(!isEnabled || !store.hasStrokes)
                .accessibilityLabel("Clear writing")
            }

            // White paper and black ink stay fixed so recognition keeps contrast in Dark Mode.
            PencilCanvasView(store: store, isEnabled: isEnabled)
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 260)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                }
                .overlay {
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 28)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Handwriting pad")
                .accessibilityHint("Write with Apple Pencil")
        }
    }
}
