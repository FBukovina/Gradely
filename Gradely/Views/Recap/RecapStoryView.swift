import Observation
import SwiftUI

/// Progress of the current slide. Only the progress bar reads it, so the
/// 20 ticks a second don't redraw the slide.
@MainActor @Observable
final class RecapPlayback {
    var progress: Double = 0
    var isHeld = false
    var isPausedByUser = false

    var isPaused: Bool { isHeld || isPausedByUser }
}

/// Gradey Recap as full-screen stories: tap right for the next slide, left
/// for the previous one, hold to pause, swipe down to close.
struct RecapStoryView: View {
    static let slideDuration: Double = 6.5

    let store: RecapStore
    let period: RecapPeriod
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var recap: Recap?
    @State private var index = 0
    @State private var playback = RecapPlayback()
    @State private var shareURL: URL?
    /// The slide `shareURL` shows; the button is dimmed while it's another.
    @State private var shareIndex: Int?
    @State private var pressStartedAt: Date?
    @FocusState private var isFocused: Bool

    private var slides: [RecapSlide] { recap?.slides ?? [] }
    private var slide: RecapSlide? { slides.indices.contains(index) ? slides[index] : nil }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                slideColor
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.35), value: index)
                    .animation(.easeInOut(duration: 0.35), value: recap == nil)

                if let recap, let slide {
                    RecapSlideView(recap: recap, slide: slide)
                        .id(slide)
                        .transition(slideTransition)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, 72)
                        .padding(.bottom, 96)
                        .frame(maxWidth: 520)
                } else {
                    loading
                }

                touchLayer(width: proxy.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) { header }
        .overlay(alignment: .bottom) { footer }
        .environment(\.colorScheme, .light)
        #if os(iOS)
        .statusBarHidden()
        #endif
        .gradelyMacSheetSize(minWidth: 420, idealWidth: 440, minHeight: 760, idealHeight: 800)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { next(); return .handled }
        .onKeyPress(.leftArrow) { previous(); return .handled }
        .onKeyPress(.space) { playback.isPausedByUser.toggle(); return .handled }
        .sensoryFeedback(.selection, trigger: index)
        .task {
            isFocused = true
            // Seen once it's opened, even if it's closed before it finishes loading.
            store.hide(period)
            recap = store.summary(for: period)
            let full = await store.recap(for: period)
            // The timetable slide may arrive late; stay on the slide being read.
            let current = slide
            recap = full
            if let current, let position = full.slides.firstIndex(of: current) { index = position }
        }
        .task(id: TimerKey(index: index, isLoaded: recap != nil, isVoiceOver: voiceOverEnabled)) {
            await runTimer()
        }
        .task(id: ShareKey(index: index, recap: recap)) {
            // Rendering takes the main thread for a moment, so it waits until
            // the slide has settled and is skipped for slides tapped past.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let recap, let slide else { return }
            shareURL = RecapShareImage.render(recap, slide: slide, number: index + 1)
            shareIndex = index
        }
    }

    // MARK: Layers

    private var slideColor: Color {
        guard let recap, let slide else { return RecapPalette.emerald }
        return RecapPalette.background(for: slide, in: recap)
    }

    private var loading: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(RecapPalette.ink)
            Text(verbatim: AppL10n.string("recap.loading"))
                .font(.gradely(.title3).weight(.semibold))
                .foregroundStyle(RecapPalette.ink)
        }
    }

    private var slideTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 24)), removal: .opacity)
    }

    /// Taps, holds and the swipe down. Buttons sit above it in the overlays.
    private func touchLayer(width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressStartedAt == nil { pressStartedAt = Date() }
                        playback.isHeld = true
                    }
                    .onEnded { value in
                        let duration = Date().timeIntervalSince(pressStartedAt ?? Date())
                        pressStartedAt = nil
                        playback.isHeld = false
                        if value.translation.height > 120 && abs(value.translation.width) < value.translation.height {
                            dismiss()
                        } else if duration < 0.3, abs(value.translation.width) < 20, abs(value.translation.height) < 20 {
                            value.startLocation.x < width / 3 ? previous() : next()
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(spacing: Spacing.md) {
            RecapProgressBar(count: max(slides.count, 1), index: index, playback: playback)
            HStack {
                // The intro and summary already say which period it is.
                if slide != .intro && slide != .summary {
                    Text(verbatim: RecapText.title(period))
                        .font(.gradely(.subheadline).weight(.semibold))
                        .foregroundStyle(RecapPalette.ink.opacity(0.75))
                }
                Spacer()
                if !voiceOverEnabled {
                    Button {
                        playback.isPausedByUser.toggle()
                    } label: {
                        GradelyIcon(playback.isPausedByUser ? "play" : "pause", size: 18)
                            .dynamicTypeSize(.large)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RecapText.localized(playback.isPausedByUser ? "recap.play" : "recap.pause"))
                }
                Button {
                    dismiss()
                } label: {
                    GradelyIcon("cancel-01", size: 20)
                        .dynamicTypeSize(.large)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(AppL10n.string("recap.close"))
                .accessibilityIdentifier("recapCloseButton")
            }
            .foregroundStyle(RecapPalette.ink)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .frame(maxWidth: 560)
    }

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            if voiceOverEnabled {
                Button(AppL10n.string("recap.previous")) { previous() }
                    .disabled(index == 0)
                Button(AppL10n.string("recap.next")) { next() }
                    .disabled(index >= slides.count - 1)
            }
            Spacer()
            if let shareURL {
                ShareLink(item: shareURL) {
                    HStack(spacing: Spacing.sm) {
                        GradelyIcon("share-03", size: 18)
                            .dynamicTypeSize(.large)
                        Text(verbatim: AppL10n.string("recap.share"))
                            .font(.gradely(.headline))
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(RecapPalette.ink, in: Capsule())
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .disabled(shareIndex != index)
                .opacity(shareIndex == index ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: shareIndex == index)
                .accessibilityIdentifier("recapShareButton")
            }
        }
        .buttonStyle(.bordered)
        .tint(RecapPalette.ink)
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: 560)
    }

    // MARK: Playback

    private struct TimerKey: Equatable {
        let index: Int
        let isLoaded: Bool
        let isVoiceOver: Bool
    }

    private struct ShareKey: Equatable {
        let index: Int
        let recap: Recap?
    }

    /// The last slide stays put; VoiceOver users move on with the buttons.
    private func runTimer() async {
        playback.progress = index == slides.count - 1 ? 1 : 0
        guard recap != nil, !voiceOverEnabled, index < slides.count - 1 else { return }
        let tick = 0.05
        while playback.progress < 1 {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            if !playback.isPaused { playback.progress = min(1, playback.progress + tick / Self.slideDuration) }
        }
        next()
    }

    private func next() {
        guard index < slides.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) { index += 1 }
    }

    private func previous() {
        guard index > 0 else {
            playback.progress = 0
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) { index -= 1 }
    }
}

/// One segment per slide, like stories: done ones full, the current one filling.
private struct RecapProgressBar: View {
    let count: Int
    let index: Int
    let playback: RecapPlayback

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { segment in
                GeometryReader { proxy in
                    Capsule()
                        .fill(RecapPalette.ink.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(RecapPalette.ink.opacity(0.85))
                                .frame(width: proxy.size.width * fill(for: segment))
                        }
                }
                .frame(height: 4)
            }
        }
        // Segments jump to the new slide; only the current one fills smoothly.
        .transaction { $0.animation = nil }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: String(format: AppL10n.string("recap.progress"), index + 1, count)))
    }

    private func fill(for segment: Int) -> CGFloat {
        if segment < index { return 1 }
        if segment > index { return 0 }
        return CGFloat(playback.progress)
    }
}

extension View {
    /// Full screen on iOS, a sheet on the Mac.
    @ViewBuilder
    func recapStory(item: Binding<RecapPeriod?>, store: RecapStore) -> some View {
        #if os(macOS)
        sheet(item: item) { RecapStoryView(store: store, period: $0) }
        #else
        fullScreenCover(item: item) { RecapStoryView(store: store, period: $0) }
        #endif
    }
}
