import GradelyWatchShared
import SwiftUI

struct GradeyAIWatchView: View {
    @ObservedObject var model: WatchAppModel

    /// Only shown to supporters; the page is hidden for everyone else.
    var body: some View {
        chat
    }

    private var chat: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if model.aiMessages.isEmpty {
                            Text("watch.ai.ask")
                                .font(.gradely(.caption).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }

                        ForEach(model.aiMessages) { message in
                            aiBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, 4)
                }
                .onChange(of: model.aiMessages.last?.text) { _, _ in
                    if let lastID = model.aiMessages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            if let error = model.aiErrorMessage {
                Text(error)
                    .font(.gradely(.caption2))
                    .foregroundStyle(WatchBrand.canceled)
                    .lineLimit(3)
            } else if !model.isPhoneReachable {
                Text("watch.ai.bringIPhone")
                    .font(.gradely(.caption2))
                    .foregroundStyle(.secondary)
            }

            composer
        }
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 6) {
            TextField("watch.ai.message", text: $model.aiDraft)
                .textFieldStyle(.plain)
                .disabled(model.isAIStreaming)

            composerActionButton
        }
    }

    @ViewBuilder
    private var composerActionButton: some View {
        if model.isAIStreaming {
            Button {
                model.cancelAI()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.gradely(size: 9, weight: .bold))
                    .foregroundStyle(WatchBrand.onAccent)
                    .frame(width: 28, height: 28)
                    .background(WatchBrand.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("watch.ai.stop")
        } else {
            Button {
                Task { await model.sendAIMessage() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.gradely(size: 12, weight: .bold))
                    .foregroundStyle(WatchBrand.onAccent)
                    .frame(width: 28, height: 28)
                    .background(WatchBrand.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draftIsEmpty)
            .opacity(draftIsEmpty ? 0.38 : 1)
            .accessibilityLabel("watch.ai.send")
        }
    }

    private var draftIsEmpty: Bool {
        model.aiDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func aiBubble(_ message: WatchAIChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: 16)
            } else {
                Image(systemName: "sparkles")
                    .font(.gradely(size: 8, weight: .bold))
                    .foregroundStyle(WatchBrand.onAccent)
                    .frame(width: 16, height: 16)
                    .background(WatchBrand.gradient, in: Circle())
                    .accessibilityHidden(true)
            }

            bubbleBody(message)

            if message.role == .assistant {
                Spacer(minLength: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private func bubbleBody(_ message: WatchAIChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
            Group {
                if message.text.isEmpty && message.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(WatchBrand.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .accessibilityLabel("watch.ai.responding")
                } else {
                    Text(message.text)
                        .font(.gradely(.caption))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
            .foregroundStyle(message.role == .user ? WatchBrand.onAccent : .white)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(message.role == .user ? AnyShapeStyle(WatchBrand.gradient) : AnyShapeStyle(.white.opacity(0.08)))
            }

            if message.role == .assistant, !message.text.isEmpty {
                Text("watch.ai.generated")
                    .font(.gradely(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
