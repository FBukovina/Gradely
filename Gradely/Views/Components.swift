import AuthenticationServices
import SwiftUI

extension Notification.Name {
    static let gradelySchoolAccountDidChange = Notification.Name("gradelySchoolAccountDidChange")
}

// MARK: - Card surface

/// Elevated content surface used throughout the app in place of ad-hoc glass.
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.lg
    var backgroundOpacity: Double = 1
    var cornerRadius: CGFloat = Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.gradelySecondaryGroupedBackground.opacity(backgroundOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Settings-local presentation

/// Quiet teal-tinted background shared by Settings and the modal surfaces
/// launched from it. This stays separate from the app-wide card treatment.
struct SettingsModalBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark
            ? Color(.sRGB, red: 0.008, green: 0.045, blue: 0.046, opacity: 1)
            : Color.gradelyGroupedBackground)
            .overlay {
                if colorScheme == .light {
                    Brand.primary.opacity(0.018)
                }
            }
            .ignoresSafeArea()
    }
}

private struct SettingsModalSurfaceShape: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? Color(.sRGB, red: 0.045, green: 0.140, blue: 0.130, opacity: 1)
                    : Color.gradelySecondaryGroupedBackground
            )
            .overlay {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(Brand.primary.opacity(0.035))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.025)
                            : Brand.primary.opacity(0.075),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.06 : 0.035),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

/// The flat 28-point surface used inside Settings-adjacent sheets.
struct SettingsModalSurface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                SettingsModalSurfaceShape()
            }
    }
}

/// Large Settings-style title with a compact Hugeicons close glyph in the
/// existing 48-point dismissal target.
struct SettingsModalHeader: View {
    let title: LocalizedStringKey
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(title)
                .font(.gradelyDisplay(size: 36))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 60)
                .accessibilityAddTraits(.isHeader)

            Button(action: onDismiss) {
                GradelyModalCloseLabel(size: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppL10n.string("action.ok"))
            .accessibilityIdentifier("modalDismissButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact circular close control used by modal headers and macOS sheet overlays.
struct GradelyModalCloseLabel: View {
    var size: CGFloat = 32

    var body: some View {
        GradelyIcon("cancel-01", size: 15)
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Brand.primary.opacity(0.10), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            }
            .contentShape(Circle())
    }
}

/// Compact, unboxed Settings icon. The visible glyph is intentionally small;
/// the consuming row remains responsible for its full interactive target.
struct SettingsModalIcon: View {
    static let frameSize: CGFloat = 32

    let name: String
    var color: Color = Brand.primary.opacity(0.88)
    var size: CGFloat = 17

    var body: some View {
        GradelyIcon(name, size: size)
            .foregroundStyle(color)
            .frame(width: Self.frameSize, height: Self.frameSize)
    }
}

/// Compact semantic icon for flows that already use SF Symbol-style names.
/// `GradelyIcon` resolves these through the app's Hugeicons mapping.
struct SettingsModalSystemIcon: View {
    let systemName: String
    var color: Color = Brand.primary.opacity(0.88)
    var size: CGFloat = 17

    var body: some View {
        GradelyIcon(systemName: systemName, size: size)
            .foregroundStyle(color)
            .frame(width: SettingsModalIcon.frameSize, height: SettingsModalIcon.frameSize)
    }
}

/// Settings-style heading used by authentication and onboarding flows.
struct SettingsModalFlowHero: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var titleSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            SettingsModalSystemIcon(systemName: icon)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.gradelyDisplay(size: titleSize))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsModalDisclosureIcon: View {
    var body: some View {
        GradelyIcon("arrow-right-01", size: 14)
            .foregroundStyle(Color.secondary.opacity(0.58))
            .frame(width: 24, height: 24)
    }
}

struct SettingsModalRowDivider: View {
    var leadingInset: CGFloat = 20 + SettingsModalIcon.frameSize + Spacing.md

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}

struct SettingsModalSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.footnote.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    @ViewBuilder
    func settingsModalNavigationChrome() -> some View {
        #if os(iOS)
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        #else
        self.navigationTitle("")
        #endif
    }
}

// MARK: - Grade badge

/// Tonal badge showing a grade or average, colored by performance band.
struct GradeBadge: View {
    let text: String
    var band: GradeBand
    var size: Size = .regular

    enum Size {
        case small, regular, large

        var font: Font {
            switch self {
            case .small: .headline.weight(.bold)
            case .regular: .title3.weight(.bold)
            case .large: .system(size: 34, weight: .bold, design: .rounded)
            }
        }

        var minWidth: CGFloat {
            switch self {
            case .small: 40
            case .regular: 52
            case .large: 72
            }
        }

        var hPadding: CGFloat {
            switch self {
            case .small: Spacing.sm
            case .regular: Spacing.md
            case .large: Spacing.lg
            }
        }
    }

    var body: some View {
        Text(text)
            .font(size.font.monospacedDigit())
            .foregroundStyle(band.foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minWidth: size.minWidth)
            .padding(.horizontal, size.hPadding)
            .padding(.vertical, size == .large ? Spacing.md : Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(band.soft)
            )
    }
}

// MARK: - Status chip

/// Small tonal capsule for metadata (type, weight, points, absence).
struct StatusChip: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.sm + 2)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Risk capsule bar

/// Thin progress capsule showing absence percentage relative to the school
/// threshold; falls back to a 0–100 % scale when no threshold is known.
struct RiskCapsuleBar: View {
    let percentage: Double
    let threshold: Double?
    let level: AbsenceRiskLevel

    private var fraction: Double {
        if let threshold, threshold > 0 {
            return min(max(percentage / threshold, 0), 1)
        }
        return min(max(percentage / 100, 0), 1)
    }

    private var fillColor: Color {
        threshold == nil ? Color.secondary.opacity(0.5) : level.color
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gradelyTertiaryFill)
                if fraction > 0 {
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(geo.size.width * fraction, 6))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Circular progress ring showing absence percentage relative to the school
/// threshold; falls back to a 0–100 % scale when no threshold is known.
struct AbsenceRiskRing: View {
    let percentage: Double
    let threshold: Double?
    let level: AbsenceRiskLevel
    var size: CGFloat = 38
    var lineWidth: CGFloat = 4.5

    private var fraction: Double {
        if let threshold, threshold > 0 {
            return min(max(percentage / threshold, 0), 1)
        }
        return min(max(percentage / 100, 0), 1)
    }

    private var fillColor: Color {
        threshold == nil ? Color.secondary.opacity(0.5) : level.color
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(fillColor.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(fillColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

// MARK: - GitHub mark

struct GitHubIcon: View {
    var size: CGFloat = 16

    var body: some View {
        Image("GitHubMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Account & Settings entry

/// Toolbar button that opens the unified Account & Settings sheet.
/// Shared by every primary tab, including Meals.
struct AccountSettingsButton: View {
    var accountHub: AnyView?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isAccountHubPresented = false

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        trigger
            .sheet(isPresented: $isAccountHubPresented) {
                presentedAccountHub
            }
        #else
        if horizontalSizeClass == .regular {
            trigger
                .fullScreenCover(isPresented: $isAccountHubPresented) {
                    presentedAccountHub
                }
        } else {
            trigger
                .sheet(isPresented: $isAccountHubPresented) {
                    presentedAccountHub
                }
        }
        #endif
    }

    private var trigger: some View {
        Button {
            isAccountHubPresented = true
        } label: {
            GradelyIcon(systemName: "gearshape.fill")
                .gradelyToolbarIconButton()
        }
        .disabled(accountHub == nil)
        .accessibilityLabel(AppL10n.string("settings.title"))
        .accessibilityIdentifier("openAccountHubButton")
    }

    @ViewBuilder
    private var presentedAccountHub: some View {
        if let accountHub {
            accountHub
        } else {
            EmptyView()
        }
    }
}

// MARK: - Gradey AI entry

struct GradeyAIToolbarButton: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            GradelyIcon(systemName: "sparkles")
                .gradelyToolbarIconButton()
        }
        .accessibilityLabel(AppL10n.string("gradey.ai.title"))
        .accessibilityIdentifier("gradeyAIButton")
    }
}

// MARK: - Stat tile

/// Compact label/value pair used in the overview hero, rendered on the brand gradient.
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    GradelyIcon(systemName: systemImage)
                        .font(.caption2.weight(.bold))
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(Brand.onAccent.opacity(0.7))

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section header

/// Small uppercase tracked label used to separate content sections.
struct SectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Primary button

/// Full-width gradient CTA used for the primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Brand.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md + 2)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .shadow(
                color: Brand.primary.opacity(isEnabled ? 0.45 : 0),
                radius: 16,
                x: 0,
                y: 8
            )
            .saturation(isEnabled ? 1 : 0.25)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(isEnabled && configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

// MARK: - Sign in with Apple

/// A single Apple sign-in control in every build configuration. UI tests swap
/// the system authorization sheet for the mock action without adding a second
/// visible button to the screen.
struct GradelyAppleSignInButton: View {
    let isLoading: Bool
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    let onMockSignIn: () -> Void

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestingMockAPI") {
                Button(action: onMockSignIn) {
                    GradelyLabel("gradey.auth.signInWithApple", systemImage: "apple.logo")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.black, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                nativeButton
            }
            #else
            nativeButton
            #endif
        }
        .disabled(isLoading)
        .accessibilityIdentifier("gradeyIDAppleButton")
    }

    private var nativeButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.email, .fullName]
        } onCompletion: { result in
            onCompletion(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}

// MARK: - Brand text field

/// Rounded filled container for text fields, replacing the stock rounded border.
struct BrandFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.gradelyTertiaryFill)
            )
    }
}

extension View {
    func brandField() -> some View { modifier(BrandFieldStyle()) }

    @ViewBuilder
    func gradelyModalDismissButton(_ dismiss: @escaping () -> Void) -> some View {
        #if os(macOS)
        overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                GradelyModalCloseLabel()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(.top, 16)
            .padding(.trailing, Spacing.lg)
            .accessibilityLabel(AppL10n.string("action.done"))
            .accessibilityIdentifier("modalDismissButton")
        }
        #else
        toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppL10n.string("action.ok")) {
                    dismiss()
                }
                .accessibilityIdentifier("modalDismissButton")
            }
        }
        #endif
    }
}

// MARK: - Aurora background

/// Layered teal "aurora" glow backdrop used app-wide (login, tabs, settings).
struct AuroraBackground: View {
    enum Style {
        case standard
        case accountSettings
    }

    @Environment(\.colorScheme) private var colorScheme

    var style: Style = .standard

    var body: some View {
        ZStack {
            Color.gradelyGroupedBackground
            GeometryReader { geo in
                switch style {
                case .standard:
                    ZStack {
                        glow(Brand.auroraGlows[0], size: geo.size.width * 1.6)
                            .position(x: geo.size.width * 0.52, y: geo.size.height * 0.02)
                        glow(Brand.auroraGlows[1], size: geo.size.width * 1.15)
                            .position(x: geo.size.width * 1.05, y: geo.size.height * 0.26)
                        glow(Brand.auroraGlows[2], size: geo.size.width * 1.05)
                            .position(x: -geo.size.width * 0.08, y: geo.size.height * 0.62)
                    }
                case .accountSettings:
                    ZStack {
                        glow(
                            Brand.primary.opacity(colorScheme == .dark ? 0.15 : 0.10),
                            size: geo.size.width * 0.92,
                            blurRadius: 42
                        )
                        .position(x: geo.size.width * 0.68, y: geo.size.height * 0.08)

                        glow(
                            Brand.secondary.opacity(colorScheme == .dark ? 0.09 : 0.07),
                            size: geo.size.width * 0.72,
                            blurRadius: 38
                        )
                        .position(x: geo.size.width * 0.12, y: geo.size.height * 0.28)

                        glow(
                            Brand.primary.opacity(colorScheme == .dark ? 0.06 : 0.05),
                            size: geo.size.width * 0.78,
                            blurRadius: 44
                        )
                        .position(x: geo.size.width * 0.98, y: geo.size.height * 0.52)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func glow(
        _ color: Color,
        size: CGFloat,
        blurRadius: CGFloat = 55
    ) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: blurRadius)
    }
}

extension View {
    /// Applies the app-wide aurora gradient behind content.
    func gradelyScreenBackground() -> some View {
        background { AuroraBackground() }
    }
}
