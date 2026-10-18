import GradelyWatchShared
import SwiftUI

struct CurrentLessonView: View {
    @ObservedObject var model: WatchAppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let page = GradelyWatchSyncCodec.nowPage(from: model.timetable, now: context.date)
            content(for: page, now: context.date)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(for page: GradelyWatchNowPage, now: Date) -> some View {
        switch page {
        case .noTimetable:
            WatchStatusPage(
                systemImage: "calendar",
                title: String(localized: "watch.noTimetable.title"),
                detail: String(localized: "watch.noTimetable.detail"),
                refresh: refreshAction
            )
        case .stale:
            WatchStatusPage(
                systemImage: "arrow.clockwise",
                title: String(localized: "watch.stale.title"),
                detail: String(localized: "watch.stale.detail"),
                refresh: refreshAction
            )
        case .doneForToday:
            WatchStatusPage(
                systemImage: "checkmark.circle.fill",
                title: String(localized: "watch.done.title")
            )
        case .inLesson(let lesson, let progress):
            lessonHero(
                lesson: lesson,
                status: lesson.isCanceled
                    ? String(localized: "watch.status.canceled")
                    : String(localized: "watch.status.now"),
                statusColor: lesson.isCanceled ? WatchBrand.canceled : WatchBrand.primary,
                progress: progress
            )
        case .betweenLessons(let next, let progress, _):
            lessonHero(
                lesson: next,
                status: next.startDate.map {
                    String(format: String(localized: "watch.status.in"), WatchLessonFormatting.remaining(until: $0, now: now))
                } ?? String(localized: "watch.status.upNext"),
                statusColor: WatchBrand.primary,
                progress: progress
            )
        }
    }

    /// Full subject name, status with room and teacher, a thin progress bar and
    /// the lesson's start and end.
    private func lessonHero(
        lesson: GradelyWatchTimetableLesson,
        status: String,
        statusColor: Color,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)

            Text(lesson.detailTitle)
                .font(.gradely(.title2).weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .strikethrough(lesson.isCanceled)

            HStack(spacing: 4) {
                Text(status)
                    .foregroundStyle(statusColor)
                    .fontWeight(.bold)
                if let meta = metaLine(for: lesson) {
                    Text(verbatim: "· " + meta)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.gradely(.caption))
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            WatchProgressBar(
                progress: progress,
                color: lesson.isCanceled ? WatchBrand.canceled : WatchBrand.primary
            )
            .padding(.top, 4)

            HStack {
                Text(WatchLessonFormatting.time(lesson.startDate))
                    .strikethrough(lesson.isCanceled)
                Spacer()
                Text(WatchLessonFormatting.time(lesson.endDate))
                    .strikethrough(lesson.isCanceled)
            }
            .font(.gradely(.caption).weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    /// Manual refresh where it matters: the app already refreshes on launch and
    /// whenever the iPhone syncs, so lesson pages don't carry a button.
    private var refreshAction: WatchStatusPage.Refresh {
        WatchStatusPage.Refresh(isRunning: model.isSyncing) {
            Task { await model.refreshTimetable() }
        }
    }

    private func metaLine(for lesson: GradelyWatchTimetableLesson) -> String? {
        let parts = [lesson.room, lesson.teacher].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct WatchProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

struct WatchStatusPage: View {
    struct Refresh {
        let isRunning: Bool
        let perform: () -> Void
    }

    let systemImage: String
    let title: String
    var detail: String?
    var refresh: Refresh?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.gradely(.title2).weight(.semibold))
                .foregroundStyle(WatchBrand.primary)
            Text(title)
                .font(.gradely(.headline).weight(.bold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.gradely(.caption2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let refresh {
                Button(action: refresh.perform) {
                    if refresh.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Label("watch.refresh", systemImage: "arrow.clockwise")
                            .font(.gradely(.caption).weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .tint(WatchBrand.primary)
                .disabled(refresh.isRunning)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 6)
    }
}
