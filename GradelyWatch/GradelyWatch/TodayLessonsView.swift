import GradelyWatchShared
import SwiftUI

/// The rest of today's lessons, next one first, as plain rows.
struct TodayLessonsView: View {
    @ObservedObject var model: WatchAppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let lessons = GradelyWatchSyncCodec.remainingLessonsToday(
                from: model.timetable,
                now: context.date
            )
            if lessons.isEmpty {
                WatchStatusPage(
                    systemImage: "calendar.badge.checkmark",
                    title: String(localized: "watch.noMoreLessons.title")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Text("watch.today")
                        .font(.gradely(.caption).weight(.bold))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)

                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                        TodayLessonRow(
                            lesson: lesson,
                            countdown: index == 0
                                ? lesson.startDate.map { WatchLessonFormatting.remaining(until: $0, now: context.date) }
                                : nil
                        )
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct TodayLessonRow: View {
    let lesson: GradelyWatchTimetableLesson
    /// Time until the lesson starts; shown on the next lesson only.
    let countdown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(lesson.detailTitle)
                    .font(.gradely(.headline).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(WatchLessonFormatting.time(lesson.startDate))
                    .font(.gradely(.caption).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(detailLine)
                .font(.gradely(.caption2))
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    /// "34 min · 24 · Novák · Room" as one run of text, so it wraps instead of
    /// truncating; the countdown and change label keep their colours.
    private var detailLine: AttributedString {
        var parts: [AttributedString] = []
        if let countdown {
            var part = AttributedString(countdown)
            part.foregroundColor = WatchBrand.primary
            part.font = .gradely(.caption2).weight(.bold)
            parts.append(part)
        }
        for value in [lesson.room, lesson.teacher].compactMap({ $0 }) where !value.isEmpty {
            var part = AttributedString(value)
            part.foregroundColor = Color.secondary
            parts.append(part)
        }
        if let change = lesson.changeKind.shortTitle {
            var part = AttributedString(String(localized: String.LocalizationValue(change)))
            part.foregroundColor = lesson.changeKind.color
            part.font = .gradely(.caption2).weight(.bold)
            parts.append(part)
        }
        var separator = AttributedString(" · ")
        separator.foregroundColor = Color.secondary
        return parts.dropFirst().reduce(parts.first ?? AttributedString()) { $0 + separator + $1 }
    }
}
