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

/// Hosts the PencilKit surface in an opaque UIKit paper view.
///
/// SwiftUI `clipShape` and overlays on top of `PKCanvasView` can hide the ink
/// layer on iPad while still capturing strokes. Corner radius and the ruling
/// line stay in this container instead.
final class PencilPaperView: UIView {
    let canvas = PKCanvasView()
    private let ruling = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .white
        isOpaque = true
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor

        ruling.translatesAutoresizingMaskIntoConstraints = false
        ruling.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        ruling.isUserInteractionEnabled = false
        addSubview(ruling)

        canvas.translatesAutoresizingMaskIntoConstraints = false
        // Clear so the ruling shows through. Ink still draws on this view.
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.overrideUserInterfaceStyle = .light
        // Fixed sRGB black so Dark Mode cannot remap the ink to an invisible color.
        canvas.tool = PKInkingTool(.pen, color: UIColor(red: 0, green: 0, blue: 0, alpha: 1), width: 16)
        addSubview(canvas)

        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),

            ruling.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            ruling.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            ruling.centerYAnchor.constraint(equalTo: centerYAnchor),
            ruling.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
}

/// PencilKit writing surface for the word and the blank.
struct PencilCanvasView: UIViewRepresentable {
    var store: PencilCanvasStore
    var isEnabled: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> PencilPaperView {
        let paper = PencilPaperView()
        paper.canvas.delegate = context.coordinator
        paper.canvas.isUserInteractionEnabled = isEnabled
        store.canvas = paper.canvas
        return paper
    }

    func updateUIView(_ paper: PencilPaperView, context: Context) {
        context.coordinator.store = store
        store.canvas = paper.canvas
        paper.canvas.delegate = context.coordinator
        paper.canvas.isUserInteractionEnabled = isEnabled
        paper.alpha = isEnabled ? 1 : 0.55
        // Do not assign `drawing` or `tool` here. Rewriting them clears or
        // redraws the surface and can make strokes vanish on device.
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var store: PencilCanvasStore

        init(store: PencilCanvasStore) {
            self.store = store
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let hasInk = !canvasView.drawing.strokes.isEmpty
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.store.hasStrokes != hasInk {
                    self.store.hasStrokes = hasInk
                }
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
                .accessibilityLabel("Handwriting pad")
                .accessibilityHint("Write with Apple Pencil")
        }
    }
}
