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

/// PencilKit writing surface for word production and sentence cloze.
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
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    store.clear()
                }
                .font(.subheadline)
                .disabled(!isEnabled || !store.hasStrokes)
                .accessibilityLabel("Clear writing")
            }

            // White paper and black ink stay fixed so recognition keeps contrast in Dark Mode.
            PencilCanvasView(store: store, isEnabled: isEnabled)
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                )
                .accessibilityLabel("Handwriting pad")
                .accessibilityHint("Write with Apple Pencil")
        }
    }
}
