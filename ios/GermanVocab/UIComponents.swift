import SwiftUI

// MARK: - Shared controls used inside native containers

struct AppPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(AppTheme.press, value: configuration.isPressed)
    }
}

struct ProgressRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.hairline)
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: max(4, geo.size.width * min(max(progress, 0), 1)))
                    .animation(AppTheme.progress, value: progress)
            }
        }
        .frame(height: 3)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

struct LearningRing: View {
    let progress: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AppTheme.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(AppTheme.progress, value: progress)
        }
        .accessibilityHidden(true)
    }
}

struct KindLabel: View {
    let isNew: Bool

    var body: some View {
        Text(isNew ? "NEW" : "REVIEW")
            .font(AppTheme.micro())
            .tracking(1.2)
            .foregroundStyle(isNew ? AppTheme.positive : AppTheme.der)
            .accessibilityLabel(isNew ? "New word" : "Review")
    }
}

struct RatingKey: View {
    let title: String
    let hint: String
    let tint: Color
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(AppTheme.body().weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(hint)
                    .font(AppTheme.micro())
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(tint)
                    .frame(width: 28, height: 3)
                    .padding(.top, 8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(AppPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}
