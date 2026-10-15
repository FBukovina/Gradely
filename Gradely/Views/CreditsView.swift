import SwiftUI

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ModalNavigationContainer {
            ZStack {
                SettingsBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        SettingsModalHeader(
                            title: "credits.title",
                            onDismiss: dismiss.callAsFunction
                        )

                        header
                        team
                        bakalariAttribution
                        if SchoolProvider.eduPage.isOfferedForNewSignIn {
                            eduPageAttribution
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("creditsScreen")
            }
            .settingsModalNavigationChrome()
        }
        .gradelyMacSheetSize(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 640)
    }

    private var header: some View {
        Link(destination: AppLinks.opensideWebURL) {
            SettingsSurface {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("credits.madeBy")
                        .font(.gradely(.caption).weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .kerning(0.4)

                    opensideWordmark

                    HStack(spacing: Spacing.xs) {
                        Text("openside.tech")
                            .font(.gradely(.subheadline).weight(.semibold))
                            .foregroundStyle(Brand.primary)

                        GradelyIcon("arrow-up-right-01", size: 13)
                            .foregroundStyle(Brand.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("creditsOpenSideLink")
    }

    private var opensideWordmark: some View {
        HStack(spacing: 0) {
            Text("Open")
                .foregroundStyle(.primary)
            Text("Side")
                .foregroundStyle(Color(red: 0.45, green: 0.18, blue: 0.82))
        }
        .font(.gradelyDisplay(size: 32))
    }

    private var team: some View {
        SettingsSurface(padding: 0) {
            VStack(spacing: 0) {
                CreditPersonRow(
                    role: AppL10n.string("credits.role.leadDeveloper"),
                    name: "Filip Bukovina",
                    email: AppLinks.filipEmailURL,
                    instagram: AppLinks.filipInstagramURL
                )

                SettingsRowDivider(leadingInset: 20)

                CreditPersonRow(
                    role: AppL10n.string("credits.role.leadGraphics"),
                    name: "Tomáš Vlk",
                    email: AppLinks.tomasEmailURL,
                    instagram: nil
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("creditsTeam")
    }

    private var bakalariAttribution: some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("bakalari.attribution.title")
                    .font(.gradely(.headline))
                Text("bakalari.attribution.message")
                    .font(.gradely(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("creditsBakalariAttribution")
    }

    private var eduPageAttribution: some View {
        SettingsSurface {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("edupage.attribution.title")
                    .font(.gradely(.headline))
                Text("edupage.attribution.message")
                    .font(.gradely(.footnote))
                    .foregroundStyle(.secondary)
                Link("EdupageAPI/edupage-api", destination: URL(string: "https://github.com/EdupageAPI/edupage-api")!)
                    .font(.gradely(.footnote).weight(.semibold))
                    .foregroundStyle(Brand.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("creditsEduPageAttribution")
    }
}

private struct CreditPersonRow: View {
    let role: String
    let name: String
    let email: URL
    let instagram: URL?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            SettingsIcon(name: "user")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(role)
                        .font(.gradely(.caption).weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .kerning(0.4)

                    Text(name)
                        .font(.gradely(.headline))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Link(destination: email) {
                        CreditLinkLabel(
                            title: email.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
                            iconName: "mail-01"
                        )
                    }

                    if let instagram {
                        Link(destination: instagram) {
                            CreditLinkLabel(
                                title: "Instagram",
                                iconName: "camera-01"
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
    }
}

private struct CreditLinkLabel: View {
    let title: String
    let iconName: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            GradelyIcon(iconName, size: 14)
                .frame(width: 18, height: 18)

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GradelyIcon("arrow-up-right-01", size: 11)
        }
        .font(.gradely(.footnote).weight(.semibold))
        .foregroundStyle(Brand.primary)
    }
}

#Preview {
    CreditsView()
}
