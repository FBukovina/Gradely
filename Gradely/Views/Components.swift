import SwiftUI

// MARK: - Card surface

/// Elevated content surface used throughout the app in place of ad-hoc glass.
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
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

// MARK: - Account menu

/// Toolbar menu showing the signed-in user plus the repository link and logout action.
/// Shared by the Marks and Timetable tabs.
struct AccountMenu: View {
    let user: UserResponse?
    let supportTipProvider: any SupportTipProviding
    let onSignedOut: () -> Void
    @State private var isSupportSheetPresented = false

    var body: some View {
        Menu {
            if let user {
                Section {
                    Text(user.fullName)
                    if let schoolName = user.displaySchoolName {
                        Text(schoolName)
                    }
                    if let className = user.userClass?.abbrev {
                        Text(className)
                    }
                }
            }

            Button {
                isSupportSheetPresented = true
            } label: {
                Label(String(localized: "support.tips.menu"), systemImage: "heart.fill")
            }
            .accessibilityIdentifier("supportGradelyButton")

            Link(destination: AppLinks.githubRepositoryURL) {
                Label {
                    Text("github.repository")
                } icon: {
                    GitHubIcon()
                }
            }
            .accessibilityIdentifier("githubRepositoryLink")

            Button(role: .destructive) {
                onSignedOut()
            } label: {
                Label(String(localized: "action.logout"), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityIdentifier("logoutButton")
        } label: {
            Image(systemName: "person.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Brand.primary)
                .frame(width: 30, height: 30)
                .background(Brand.primary.opacity(0.15), in: Circle())
        }
        .accessibilityLabel(String(localized: "account.menu"))
        .accessibilityIdentifier("accountMenuButton")
        .sheet(isPresented: $isSupportSheetPresented) {
            SupportTipView(
                viewModel: SupportTipViewModel(
                    supportTipProvider: supportTipProvider
                )
            )
        }
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
                    Image(systemName: systemImage)
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
    }
}

// MARK: - Primary button

/// Full-width gradient CTA used for the primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Brand.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md + 2)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .shadow(color: Brand.primary.opacity(0.45), radius: 16, x: 0, y: 8)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
                    .fill(Color(.tertiarySystemFill))
            )
    }
}

extension View {
    func brandField() -> some View { modifier(BrandFieldStyle()) }
}

// MARK: - Aurora background

/// Layered teal "aurora" glow backdrop used on the sign-in screen (Quipee-style).
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            GeometryReader { geo in
                ZStack {
                    glow(Brand.auroraGlows[0], size: geo.size.width * 1.6)
                        .position(x: geo.size.width * 0.52, y: geo.size.height * 0.02)
                    glow(Brand.auroraGlows[1], size: geo.size.width * 1.15)
                        .position(x: geo.size.width * 1.05, y: geo.size.height * 0.26)
                    glow(Brand.auroraGlows[2], size: geo.size.width * 1.05)
                        .position(x: -geo.size.width * 0.08, y: geo.size.height * 0.62)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 55)
    }
}
