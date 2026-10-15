import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Palette

/// Gradey AI's own visual identity. The rest of the app uses the calm
/// Settings-style surfaces; AI intentionally reads as a distinct, living space.
enum GradeyAIPalette {
    static func base(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 0.008, green: 0.045, blue: 0.046, opacity: 1)
            : Color(.sRGB, red: 0.937, green: 0.976, blue: 0.965, opacity: 1)
    }

    static func userBubble(_ colorScheme: ColorScheme) -> LinearGradient {
        let strength = colorScheme == .dark ? 1.0 : 0.72
        return LinearGradient(
            colors: [Brand.primary.opacity(0.28 * strength), Brand.secondary.opacity(0.18 * strength)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Background

/// Teal/emerald aurora. It rests while idle and drifts and brightens only while
/// Gradey is replying, so idle screens cost nothing and never keep UI tests
/// waiting for animations. Reduce Motion keeps the brighter state static.
struct GradeyAIBackground: View {
    var isActive = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeSince: Date? = nil

    init(isActive: Bool = false) {
        self.isActive = isActive
    }

    var body: some View {
        ZStack {
            mesh(phase: 0, isBoosted: false)

            if let activeSince {
                Group {
                    if reduceMotion {
                        mesh(phase: 0, isBoosted: true)
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                            mesh(phase: context.date.timeIntervalSince(activeSince) * 0.6, isBoosted: true)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: activeSince)
        .onChange(of: isActive, initial: true) { _, active in
            activeSince = active ? Date() : nil
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func mesh(phase: Double, isBoosted: Bool) -> some View {
        let base = GradeyAIPalette.base(colorScheme)
        let strength = (colorScheme == .dark ? 0.9 : 0.55) * (isBoosted ? 1.25 : 1)

        func drift(_ offset: Double, _ amount: Float) -> Float {
            Float(sin(phase + offset)) * amount
        }
        func glow(_ color: Color, _ amount: Double) -> Color {
            base.mix(with: color, by: min(1, amount * strength))
        }

        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + drift(0, 0.14), 0], [1, 0],
            [0, 0.34 + drift(1.3, 0.08)], [0.5 + drift(2.1, 0.18), 0.30 + drift(0.7, 0.1)], [1, 0.40 + drift(2.8, 0.08)],
            [0, 1], [0.5, 1], [1, 1],
        ]
        let colors: [Color] = [
            glow(Brand.primary, 0.42), glow(Brand.secondary, 0.30), glow(Brand.primary, 0.36),
            glow(Brand.secondary, 0.14), glow(Brand.primary, 0.12), glow(Brand.secondary, 0.14),
            base, base, base,
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }
}

// MARK: - Orb

/// Gradey AI's signature mark: a glowing gradient disc with a sparkle glyph.
struct GradeyAIOrb: View {
    var size: CGFloat = 28
    var isActive = false
    var icon: String = "sparkles"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGFloat = 28, isActive: Bool = false, icon: String = "sparkles") {
        self.size = size
        self.isActive = isActive
        self.icon = icon
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.gradient)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.42), .clear],
                        center: UnitPoint(x: 0.3, y: 0.22),
                        startRadius: 0,
                        endRadius: size * 0.62
                    )
                )
            GradelyIcon(icon, size: size * 0.5)
                .foregroundStyle(Brand.onAccent)
        }
        .frame(width: size, height: size)
        .background { glow }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glow: some View {
        let halo = Circle()
            .fill(Brand.primary)
            .blur(radius: size * 0.34)
        if isActive && !reduceMotion {
            halo.phaseAnimator([false, true]) { content, expanded in
                content
                    .opacity(expanded ? 0.72 : 0.32)
                    .scaleEffect(expanded ? 1.2 : 0.92)
            } animation: { _ in
                .easeInOut(duration: 1.5)
            }
        } else {
            halo.opacity(isActive ? 0.55 : 0.38)
        }
    }
}

// MARK: - Glow border

/// Teal→emerald rim with a soft halo. Brightens when active and rotates only
/// while `isAnimating` (a reply is streaming). Used by the composer.
struct GradeyAIGlowBorder: ViewModifier {
    let cornerRadius: CGFloat
    let isActive: Bool
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(cornerRadius: CGFloat, isActive: Bool, isAnimating: Bool) {
        self.cornerRadius = cornerRadius
        self.isActive = isActive
        self.isAnimating = isAnimating
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Brand.primary)
                    .blur(radius: isActive ? 18 : 12)
                    .opacity(isActive ? 0.34 : 0.12)
                    .animation(.easeOut(duration: 0.3), value: isActive)
                    .allowsHitTesting(false)
            }
            .overlay {
                Group {
                    if isAnimating && !reduceMotion {
                        TimelineView(.animation) { context in
                            let seconds = context.date.timeIntervalSinceReferenceDate
                            rim(angle: .degrees(seconds.truncatingRemainder(dividingBy: 4) / 4 * 360))
                        }
                    } else {
                        rim(angle: .degrees(0))
                    }
                }
                .allowsHitTesting(false)
            }
    }

    private func rim(angle: Angle) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    colors: [
                        Brand.primary,
                        Brand.secondary,
                        Brand.primary.opacity(0.2),
                        Brand.secondary.opacity(0.9),
                        Brand.primary,
                    ],
                    center: .center,
                    angle: angle
                ),
                lineWidth: isActive ? 1.6 : 1.1
            )
            .opacity(isActive ? 1 : 0.5)
    }
}

extension View {
    func gradeyAIGlowBorder(cornerRadius: CGFloat, isActive: Bool, isAnimating: Bool = false) -> some View {
        modifier(GradeyAIGlowBorder(cornerRadius: cornerRadius, isActive: isActive, isAnimating: isAnimating))
    }

    /// Tinted Liquid Glass used for Gradey AI chrome (never for message bubbles).
    func gradeyAIGlass(cornerRadius: CGFloat, tint: Double = 0.08, interactive: Bool = false) -> some View {
        glassEffect(
            .regular.tint(Brand.primary.opacity(tint)).interactive(interactive),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
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

/// Round glass icon button used in the Gradey AI top bars.
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
            .contentShape(Circle())
            .glassEffect(.regular.interactive(isEnabled), in: Circle())
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
            .shadow(color: Brand.primary.opacity(isEnabled ? 0.45 : 0), radius: 8, y: 2)
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
        .glassEffect(
            .regular.tint(kind.tint.opacity(0.16)),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
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

/// Soft fade into the base colour, used behind pinned bottom controls.
struct GradeyAIBottomFade: View {
    @Environment(\.colorScheme) private var colorScheme

    init() {}

    var body: some View {
        let base = GradeyAIPalette.base(colorScheme)
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
