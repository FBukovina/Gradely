import SwiftUI

/// One chat turn. User messages are compact tinted bubbles; assistant replies
/// flow as unboxed text next to the Gradey orb, followed by the AI-generated
/// disclosure and message actions.
struct GradeyAIMessageRow: View {
    let message: GradeyAIMessage
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        Group {
            if message.role == .user {
                GradeyAIUserBubble(text: message.content)
            } else {
                GradeyAIAssistantReply(message: message, canRetry: canRetry, onRetry: onRetry)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gradeyAIMessage-\(message.id)")
    }
}

private struct GradeyAIUserBubble: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 22,
            bottomLeadingRadius: 22,
            bottomTrailingRadius: 6,
            topTrailingRadius: 22,
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 48)
            Text(text)
                .font(.gradely(.body))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(GradeyAIPalette.userBubble(colorScheme), in: shape)
                .overlay {
                    shape.stroke(Brand.primary.opacity(colorScheme == .dark ? 0.32 : 0.22), lineWidth: 1)
                }
                .frame(maxWidth: 560, alignment: .trailing)
        }
    }
}

private struct GradeyAIAssistantReply: View {
    let message: GradeyAIMessage
    let canRetry: Bool
    let onRetry: () -> Void

    @State private var didCopy = false

    init(message: GradeyAIMessage, canRetry: Bool, onRetry: @escaping () -> Void) {
        self.message = message
        self.canRetry = canRetry
        self.onRetry = onRetry
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            GradeyAIOrb(size: 28)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
                footer
            }
            .frame(maxWidth: 640, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.content.isEmpty {
            switch message.status {
            case .streaming:
                GradeyAIThinkingIndicator()
                    .padding(.top, 3)
            case .failed:
                Text("gradey.ai.error.couldNotComplete")
                    .font(.gradely(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            case .complete, .cancelled:
                EmptyView()
            }
        } else {
            GradeyAIMarkdownText(markdown: message.content)
                .font(.gradely(.body))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var footer: some View {
        let showsDisclosure = !message.content.isEmpty
        let showsCopy = message.status == .complete && !message.content.isEmpty
        let showsRetry = message.status == .failed && canRetry
        let showsCancelled = message.status == .cancelled

        if showsDisclosure || showsCopy || showsRetry || showsCancelled {
            HStack(spacing: Spacing.md) {
                if showsDisclosure {
                    HStack(spacing: 4) {
                        GradelyIcon("sparkles", size: 11)
                            .foregroundStyle(Brand.gradient)
                        Text("gradey.ai.act.generated")
                    }
                    .font(.gradely(.caption2).weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                if showsCancelled {
                    Text("gradey.ai.response.cancelled")
                        .font(.gradely(.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if showsRetry {
                    Button(action: onRetry) {
                        GradelyLabel(AppL10n.string("action.retry"), systemImage: "arrow.clockwise", iconSize: 13)
                            .font(.gradely(.caption).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(GradeBand.poor.foregroundColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GradeBand.poor.foregroundColor)
                    .accessibilityIdentifier("gradeyAIRetryMessageButton")
                }

                if showsCopy {
                    Button(action: copy) {
                        GradelyIcon(didCopy ? "tick-02" : "copy-01", size: 15)
                            .foregroundStyle(didCopy ? Brand.primary : Color.secondary)
                            .frame(width: 44, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copyLabel)
                    .accessibilityIdentifier("gradeyAICopyMessageButton")
                }
            }
        }
    }

    private var copyLabel: String {
        if didCopy {
            AppL10n.string("gradey.ai.message.copied")
        } else {
            AppL10n.string("gradey.ai.message.copy")
        }
    }

    private func copy() {
        GradeyAIClipboard.copy(message.content)
        withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.2)) { didCopy = false }
        }
    }
}
