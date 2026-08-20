import SwiftUI

struct GradeyAIWatchView: View {
    @ObservedObject var model: WatchAppModel

    var body: some View {
        Group {
            if model.isRecurringSupporter {
                chat
            } else {
                lock
            }
        }
    }

    private var lock: some View {
        WatchStatusPage(
            systemImage: "lock.fill",
            title: "Gradey AI",
            detail: "Available on recurring supporter plans. Subscribe in Gradey on iPhone."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chat: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if model.aiMessages.isEmpty {
                            Text("Ask Gradey AI")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }

                        ForEach(model.aiMessages) { message in
                            aiBubble(message)
                                .id(message.id)
                        }
                    }
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
                    .font(.caption2)
                    .foregroundStyle(WatchBrand.canceled)
                    .lineLimit(3)
            } else if !model.isPhoneReachable {
                Text("Bring iPhone nearby")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                TextField("Message", text: $model.aiDraft)
                    .textFieldStyle(.plain)
                    .disabled(model.isAIStreaming)

                Button {
                    if model.isAIStreaming {
                        model.cancelAI()
                    } else {
                        Task { await model.sendAIMessage() }
                    }
                } label: {
                    Image(systemName: model.isAIStreaming ? "stop.fill" : "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WatchBrand.onAccent)
                        .frame(width: 28, height: 28)
                        .background(WatchBrand.gradient, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.isAIStreaming && model.aiDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func aiBubble(_ message: WatchAIChatMessage) -> some View {
        Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(message.role == .user ? AnyShapeStyle(WatchBrand.gradient) : AnyShapeStyle(.white.opacity(0.08)))
            }
            .foregroundStyle(message.role == .user ? WatchBrand.onAccent : .white)
    }
}
