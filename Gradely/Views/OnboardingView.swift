import SwiftUI

struct OnboardingView: View {
    let onFinished: () -> Void
    @State private var selection = 0

    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: Spacing.xl) {
                HStack {
                    Spacer()

                    Button(String(localized: "onboarding.skip")) {
                        onFinished()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
                    .accessibilityIdentifier("onboardingSkipButton")
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

                TabView(selection: $selection) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                            .padding(.horizontal, Spacing.xl)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut(duration: 0.2), value: selection)

                Button {
                    if isLastPage {
                        onFinished()
                    } else {
                        selection += 1
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Text(isLastPage ? String(localized: "onboarding.getStarted") : String(localized: "onboarding.next"))
                        Image(systemName: isLastPage ? "checkmark" : "chevron.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
                .accessibilityIdentifier("onboardingPrimaryButton")
            }
        }
    }

    private var isLastPage: Bool {
        selection == pages.count - 1
    }
}

private struct OnboardingPage: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey
    let systemImage: String

    static let pages = [
        OnboardingPage(
            id: "welcome",
            titleKey: "onboarding.welcome.title",
            bodyKey: "onboarding.welcome.body",
            systemImage: "graduationcap.fill"
        ),
        OnboardingPage(
            id: "school",
            titleKey: "onboarding.school.title",
            bodyKey: "onboarding.school.body",
            systemImage: "building.columns.fill"
        ),
        OnboardingPage(
            id: "marks",
            titleKey: "onboarding.marks.title",
            bodyKey: "onboarding.marks.body",
            systemImage: "chart.line.uptrend.xyaxis"
        )
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: Spacing.xl)

            Image(systemName: page.systemImage)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Brand.onAccent)
                .frame(width: 104, height: 104)
                .background(Brand.gradient, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .shadow(color: Brand.primary.opacity(0.35), radius: 22, x: 0, y: 12)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.md) {
                Text(page.titleKey)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                Text(page.bodyKey)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 440)

            Spacer(minLength: Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView {}
}
