import SwiftUI

/// Shared iPhone and iPad chrome. Liquid Glass stays on controls that float
/// over content. Cards, lists, and text stay on the system content layer.
enum AppMotion {
    static let reveal = Animation.smooth(duration: 0.35)
    static let step = Animation.snappy(duration: 0.32, extraBounce: 0)
}

extension View {
    /// Primary action. Uses the system prominent glass style.
    func prominentGlassCapsule() -> some View {
        buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
    }

    /// Secondary action that still sits in the glass layer.
    func glassCapsule(size: ControlSize = .large) -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(size)
    }

    /// Keeps a control from stretching across a wide iPad window.
    func actionColumn() -> some View {
        frame(maxWidth: 640)
    }
}

/// Bottom controls hosted in a safe-area bar so they pick up the scroll-edge glass.
struct BottomActionBar<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: spacing) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }
}

struct ArticleText: View {
    let article: String?
    var prominent = false

    var body: some View {
        if let article {
            Text(article)
                .font(prominent ? .title3.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(AppTheme.genderColor(for: article))
                .padding(.horizontal, prominent ? 10 : 7)
                .padding(.vertical, prominent ? 4 : 3)
                .background(AppTheme.genderColor(for: article).opacity(0.16), in: Capsule())
                .accessibilityHidden(true)
        }
    }
}

struct StatusChip: View {
    let title: String
    let tint: Color
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

struct LoadFailureView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                .prominentGlassCapsule()
                .actionColumn()
        }
    }
}
