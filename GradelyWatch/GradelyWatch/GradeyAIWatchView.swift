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
        ScrollView {
            VStack(spacing: 10) {
                WatchStatusPage(
                    systemImage: "lock.fill",
                    title: "Gradey AI",
                    detail: "Available on recurring supporter plans. Subscribe in Gradey on iPhone."
                )

                if let purchaseRefreshMessage = model.purchaseRefreshMessage {
                    Text(purchaseRefreshMessage)
                        .font(.caption2)
                        .foregroundStyle(WatchBrand.canceled)
                        .multilineTextAlignment(.center)
                } else if !model.isPhoneReachable {
                    Text("Bring iPhone nearby")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await model.refreshPurchases() }
                } label: {
                    HStack(spacing: 6) {
                        if model.isRefreshingPurchases {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(WatchBrand.onAccent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh purchases")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WatchBrand.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(WatchBrand.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isRefreshingPurchases)
                .accessibilityLabel("Refresh purchases")
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chat: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
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
                    .font(.caption2)
                    .foregroundStyle(WatchBrand.canceled)
                    .lineLimit(3)
            } else if !model.isPhoneReachable {
                Text("Bring iPhone nearby")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            composer
        }
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 6) {
            TextField("Message", text: $model.aiDraft)
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
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WatchBrand.onAccent)
                    .frame(width: 28, height: 28)
                    .background(WatchBrand.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
        } else {
            Button {
                Task { await model.sendAIMessage() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WatchBrand.onAccent)
                    .frame(width: 28, height: 28)
                    .background(WatchBrand.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draftIsEmpty)
            .opacity(draftIsEmpty ? 0.38 : 1)
            .accessibilityLabel("Send")
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
                    .font(.system(size: 8, weight: .bold))
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
        Group {
            if message.text.isEmpty && message.isStreaming {
                ProgressView()
                    .controlSize(.mini)
                    .tint(WatchBrand.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Responding")
            } else {
                Text(message.text)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .foregroundStyle(message.role == .user ? WatchBrand.onAccent : .white)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(message.role == .user ? AnyShapeStyle(WatchBrand.gradient) : AnyShapeStyle(.white.opacity(0.08)))
        }
    }
}
