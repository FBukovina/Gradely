import SwiftUI

/// The "we updated our Privacy Policy" surface.
///
/// Presented automatically, once, after updating to a release that carries a new
/// `PrivacyPolicyRevision.current`, and reachable afterwards from
/// Settings → Privacy & Data in `.review` mode.
struct PrivacyPolicyUpdateView: View {
    enum Mode {
        /// First run after the update: the accept button stays disabled until
        /// the summary has been scrolled through, and there is no way out.
        case consent
        /// Opened from Settings: read-only, dismissable, no gate.
        case review
    }

    var mode: Mode = .consent
    var onAccept: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var readProgress = PrivacyPolicyReadProgress()
    @State private var expandedChangeID: String?
    @State private var hasAppeared = false

    private var isGated: Bool { mode == .consent }

    private var isAcceptEnabled: Bool {
        readProgress.isSatisfied(voiceOverEnabled: voiceOverEnabled)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SettingsModalBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        header
                        changeList
                        footerNote
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                }
                .scrollIndicators(.visible)
                .onScrollGeometryChange(for: Double.self) { geometry in
                    PrivacyPolicyReadProgress.fraction(
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height,
                        offset: geometry.contentOffset.y + geometry.contentInsets.top
                    )
                } action: { _, fraction in
                    readProgress.update(fraction: fraction)
                }
                .accessibilityIdentifier("privacyPolicyUpdateScrollView")
            }
            .safeAreaInset(edge: .top, spacing: 0) { progressHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            .settingsModalNavigationChrome()
        }
        .interactiveDismissDisabled(isGated)
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 640)
        #endif
        .accessibilityIdentifier("privacyPolicyUpdateView")
        .accessibilityElement(children: .contain)
        .task {
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.snappy(duration: 0.42)) { hasAppeared = true }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if isGated {
                heroIcon
            } else {
                HStack(alignment: .top) {
                    heroIcon
                    Spacer(minLength: Spacing.md)
                    Button(action: dismiss.callAsFunction) {
                        GradelyModalCloseLabel(size: 48)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppL10n.string("action.done"))
                    .accessibilityIdentifier("modalDismissButton")
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("privacy.update.title")
                    .font(.gradelyDisplay(size: 36))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("privacy.update.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    String(
                        format: AppL10n.string("privacy.update.effective"),
                        PrivacyPolicyRevision.formattedEffectiveDate()
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("privacyPolicyUpdateEffectiveDate")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.88, anchor: .topLeading)
    }

    private var heroIcon: some View {
        GradelyIcon("security-lock", size: 34)
            .foregroundStyle(Brand.onAccent)
            .frame(width: 76, height: 76)
            .background(
                Brand.gradient,
                in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            )
            .shadow(color: Brand.primary.opacity(0.28), radius: 16, x: 0, y: 8)
            .accessibilityHidden(true)
    }

    // MARK: - Change breakdown

    private var changeList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("privacy.update.changes.title")

            SettingsModalSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(PrivacyPolicyRevision.changes.enumerated()), id: \.element.id) { index, change in
                        if index > 0 {
                            SettingsModalRowDivider()
                        }
                        changeRow(change)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 18)
                            .animation(
                                reduceMotion
                                    ? nil
                                    : .snappy(duration: 0.40).delay(Double(index) * 0.06 + 0.10),
                                value: hasAppeared
                            )
                    }
                }
            }
        }
    }

    private func changeRow(_ change: PrivacyPolicyChange) -> some View {
        let isExpanded = expandedChangeID == change.id

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                    expandedChangeID = isExpanded ? nil : change.id
                }
            } label: {
                HStack(alignment: .top, spacing: Spacing.md) {
                    GradelyIcon(change.iconName, size: 17)
                        .foregroundStyle(Brand.primary.opacity(0.88))
                        .frame(width: SettingsModalIcon.frameSize, height: SettingsModalIcon.frameSize)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(change.titleKey)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(change.summaryKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GradelyIcon("arrow-right-01", size: 14)
                        .foregroundStyle(Color.secondary.opacity(0.58))
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("privacyPolicyUpdateRow-\(change.id)")
            .accessibilityHint(AppL10n.string("privacy.update.row.hint"))

            if isExpanded {
                Text(change.detailKey)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, SettingsModalIcon.frameSize + Spacing.md)
                    .accessibilityIdentifier("privacyPolicyUpdateDetail-\(change.id)")
            }
        }
        .padding(20)
        .contentShape(Rectangle())
    }

    // MARK: - Footer

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("privacy.update.footer")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: AppLinks.privacyPolicyURL) {
                HStack(spacing: Spacing.xs) {
                    Text("privacy.update.fullPolicy")
                        .font(.subheadline.weight(.semibold))
                    GradelyIcon("arrow-up-right-01", size: 13)
                }
                .foregroundStyle(Brand.primary)
            }
            .accessibilityIdentifier("privacyPolicyUpdateFullPolicyLink")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(hasAppeared ? 1 : 0)
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.40).delay(0.46),
            value: hasAppeared
        )
    }

    /// Doubles as the opaque backing for the status bar: the summary scrolls
    /// under it in the full-screen presentation, which has no navigation bar.
    @ViewBuilder
    private var progressHeader: some View {
        if isGated {
            VStack(spacing: Spacing.xs) {
                ProgressView(value: isAcceptEnabled ? 1 : readProgress.fraction)
                    .tint(Brand.primary)
                    .accessibilityIdentifier("privacyPolicyUpdateProgress")
                    .accessibilityLabel(AppL10n.string("privacy.update.progress"))

                if !isAcceptEnabled {
                    Text("privacy.update.scrollHint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color.gradelyGroupedBackground)
            .animation(.snappy(duration: 0.34), value: isAcceptEnabled)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if isGated {
            Button {
                onAccept()
            } label: {
                Text("privacy.update.accept")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isAcceptEnabled)
            .accessibilityIdentifier("privacyPolicyUpdateAcceptButton")
            .padding(.horizontal, 20)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.md)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color.gradelyGroupedBackground)
        }
    }
}

extension View {
    /// Presents the mandatory policy-update surface. There is no dismiss
    /// affordance: the binding's setter is deliberately inert, and the
    /// presentation ends only once `onAccept` records the acceptance and
    /// `isPresented` becomes `false` on the next evaluation.
    @ViewBuilder
    func privacyPolicyUpdate(
        isPresented: Bool,
        onAccept: @escaping () -> Void
    ) -> some View {
        let binding = Binding(get: { isPresented }, set: { _ in })
        #if os(macOS)
        sheet(isPresented: binding) {
            PrivacyPolicyUpdateView(mode: .consent, onAccept: onAccept)
        }
        #else
        fullScreenCover(isPresented: binding) {
            PrivacyPolicyUpdateView(mode: .consent, onAccept: onAccept)
        }
        #endif
    }
}

#Preview("Consent") {
    PrivacyPolicyUpdateView(mode: .consent)
}

#Preview("Review") {
    PrivacyPolicyUpdateView(mode: .review)
}
