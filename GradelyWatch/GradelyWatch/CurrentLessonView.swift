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
                detail: String(localized: "watch.noTimetable.detail")
            )
        case .stale:
            WatchStatusPage(
                systemImage: "arrow.clockwise",
                title: String(localized: "watch.stale.title"),
                detail: String(localized: "watch.stale.detail")
            )
        case .doneForToday:
            WatchStatusPage(
                systemImage: "checkmark.circle.fill",
                title: String(localized: "watch.done.title"),
                detail: String(localized: "watch.done.detail")
            )
        case .inLesson(let lesson, let progress):
            lessonHero(
                lesson: lesson,
                status: lesson.isCanceled
                    ? String(localized: "watch.status.canceled")
                    : String(localized: "watch.status.now"),
                statusColor: lesson.isCanceled ? WatchBrand.canceled : WatchBrand.primary,
                progress: progress,
                now: now,
                subtitle: metaLine(for: lesson)
            )
        case .betweenLessons(let next, let progress, _):
            lessonHero(
                lesson: next,
                status: next.startDate.map {
                    String(format: String(localized: "watch.status.in"), WatchLessonFormatting.remaining(until: $0, now: now))
                } ?? String(localized: "watch.status.upNext"),
                statusColor: WatchBrand.primary,
                progress: progress,
                now: now,
                subtitle: [
                    Optional(String(localized: "watch.break")),
                    metaLine(for: next)
                ]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            )
        }
    }

    private func lessonHero(
        lesson: GradelyWatchTimetableLesson,
        status: String,
        statusColor: Color,
        progress: Double,
        now _: Date,
        subtitle: String?
    ) -> some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)

            ZStack {
                LessonProgressArc(progress: progress, isCanceled: lesson.isCanceled)
                    .frame(width: 118, height: 118)

                VStack(spacing: 1) {
                    Text(lesson.title)
                        .font(.title2.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .strikethrough(lesson.isCanceled)
                    Text(status)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, 8)
            }

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(WatchLessonFormatting.time(lesson.startDate))
                        .font(.headline.weight(.bold))
                        .strikethrough(lesson.isCanceled)
                    Text(String(localized: "watch.start"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(WatchLessonFormatting.time(lesson.endDate))
                        .font(.headline.weight(.bold))
                        .strikethrough(lesson.isCanceled)
                    Text(String(localized: "watch.end"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
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

struct WatchStatusPage: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(WatchBrand.primary)
            Text(title)
                .font(.headline.weight(.bold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
    }
}
