import SwiftUI

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    team
                }
                .padding(Spacing.lg)
            }
            .background(Color.gradelyGroupedBackground.ignoresSafeArea())
            .navigationTitle(String(localized: "credits.title"))
            .gradelyNavigationTitleDisplayMode(.inline)
        }
        .gradelyModalDismissButton {
            dismiss()
        }
    }

    private var header: some View {
        Link(destination: AppLinks.opensideWebURL) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Color.gradelySystemGray5, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("credits.madeBy")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.black.opacity(0.56))
                        .kerning(0.4)

                    opensideWordmark

                    HStack(spacing: Spacing.xs) {
                        Text("openside.tech")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.45, green: 0.18, blue: 0.82))

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.45, green: 0.18, blue: 0.82))
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var opensideWordmark: some View {
        HStack(spacing: 0) {
            Text("Open")
                .foregroundStyle(Color.black)
            Text("Side")
                .foregroundStyle(Color(red: 0.45, green: 0.18, blue: 0.82))
        }
        .font(.custom("SpaceGrotesk-Bold", size: 32))
    }

    private var team: some View {
        VStack(spacing: Spacing.md) {
            CreditPersonRow(
                role: String(localized: "credits.role.leadDeveloper"),
                name: "Filip Bukovina",
                email: AppLinks.filipEmailURL,
                instagram: AppLinks.filipInstagramURL
            )

            CreditPersonRow(
                role: String(localized: "credits.role.leadGraphics"),
                name: "Tomáš Vlk",
                email: AppLinks.tomasEmailURL,
                instagram: nil
            )
        }
    }
}

private struct CreditPersonRow: View {
    let role: String
    let name: String
    let email: URL
    let instagram: URL?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(role)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .kerning(0.4)

                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Link(destination: email) {
                        Label(email.absoluteString.replacingOccurrences(of: "mailto:", with: ""), systemImage: "envelope.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Brand.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    if let instagram {
                        Link(destination: instagram) {
                            Label("Instagram", systemImage: "camera.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Brand.primary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    CreditsView()
}
