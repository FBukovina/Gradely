import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Palette

enum GradeyAIPalette {
    static func userBubble(_ colorScheme: ColorScheme) -> LinearGradient {
        let strength = colorScheme == .dark ? 1.0 : 0.72
        return LinearGradient(
            colors: [Brand.primary.opacity(0.28 * strength), Brand.secondary.opacity(0.18 * strength)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Orb

/// Gradey AI's mark: a gradient disc with a sparkle glyph.
struct GradeyAIOrb: View {
    var size: CGFloat = 28
    var icon: String = "sparkles"

    init(size: CGFloat = 28, icon: String = "sparkles") {
        self.size = size
        self.icon = icon
    }

    var body: some View {
        GradelyIcon(icon, size: size * 0.5)
            .foregroundStyle(Brand.onAccent)
            .frame(width: size, height: size)
            .background(Brand.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

extension View {
    /// The plain card surface Gradey AI shares with the rest of the app.
    func gradeyAISurface(cornerRadius: CGFloat) -> some View {
        background(
            Color.gradelySecondaryGroupedBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

// MARK: - Thinking indicator

/// Three staggered gradient dots shown while a reply has not produced text yet.
struct GradeyAIThinkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    var body: some View {
        Group {
            if reduceMotion {
                dots(time: nil)
            } else {
                TimelineView(.animation) { context in
                    dots(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel(AppL10n.string("gradey.ai.responding"))
    }

    private func dots(time: TimeInterval?) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                let wave = time.map { (sin($0 * 5 - Double(index) * 0.8) + 1) / 2 } ?? 0.6
                Circle()
                    .fill(Brand.gradient)
                    .frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * wave)
                    .scaleEffect(0.8 + 0.3 * wave)
            }
        }
    }
}

// MARK: - Controls

/// Round icon button used in the Gradey AI top bars.
struct GradeyAICircleButton: View {
    let icon: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GradeyAICircleGlyph(icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct GradeyAICircleGlyph: View {
    let icon: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GradelyIcon(icon, size: 18)
            .foregroundStyle(.primary)
            .opacity(isEnabled ? 1 : 0.35)
            .frame(width: 44, height: 44)
            .background(Color.gradelySecondaryGroupedBackground, in: Circle())
            .contentShape(Circle())
    }
}

/// Gradient send / stop control inside the composer.
struct GradeyAIComposerButton: View {
    let icon: String
    let isEnabled: Bool

    var body: some View {
        GradelyIcon(icon, size: 16)
            .foregroundStyle(Brand.onAccent)
            .frame(width: 38, height: 38)
            .background(Brand.gradient, in: Circle())
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

/// Inline notice for paused service and request errors.
struct GradeyAIBanner: View {
    enum Kind {
        case paused
        case error

        var icon: String {
            switch self {
            case .paused: "pause.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .paused: .gradelySystemOrange
            case .error: GradeBand.poor.foregroundColor
            }
        }
    }

    let kind: Kind
    var title: String?
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            GradelyIcon(systemName: kind.icon, size: 17)
                .foregroundStyle(kind.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.gradely(.subheadline).weight(.semibold))
                }
                Text(message)
                    .font(title == nil ? .gradely(.subheadline) : .gradely(.caption))
                    .foregroundStyle(title == nil ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    GradelyIcon("cancel-01", size: 12)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppL10n.string("action.done"))
                .accessibilityIdentifier("gradeyAIErrorDismissButton")
            }
        }
        .padding(Spacing.md)
        .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Early-access pill shown next to the Compute allowance.
struct GradeyAIEarlyAccessBadge: View {
    var body: some View {
        Text("gradey.ai.earlyAccess.badge")
            .font(.gradely(.caption2).weight(.bold))
            .foregroundStyle(Brand.onAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Brand.gradient, in: Capsule())
            .accessibilityIdentifier("gradeyAIEarlyAccessBadge")
    }
}

/// Soft fade into the screen background, used behind pinned bottom controls.
struct GradeyAIBottomFade: View {
    init() {}

    var body: some View {
        let base = Color.gradelyGroupedBackground
        LinearGradient(colors: [base.opacity(0), base.opacity(0.92), base], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

// MARK: - Quota text

enum GradeyAIQuotaText {
    static func remaining(_ status: GradeyAIStatus?) -> String {
        guard let status else { return "" }
        return String.localizedStringWithFormat(
            AppL10n.string("gradey.ai.compute.remaining"),
            Int64(status.remaining),
            Int64(status.dailyLimit)
        )
    }

    static func reset(_ status: GradeyAIStatus?) -> String? {
        guard let resetAt = status?.resetAt else { return nil }
        return String.localizedStringWithFormat(
            AppL10n.string("gradey.ai.limit.resets"),
            resetAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguageOverride.locale))
        )
    }
}

// MARK: - Clipboard

enum GradeyAIClipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
