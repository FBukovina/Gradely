import GradelyWatchShared
import SwiftUI

struct UpcomingLessonView: View {
    @ObservedObject var model: WatchAppModel
    @State private var showingRemaining = false
    @State private var remainingToShow: [GradelyWatchTimetableLesson] = []

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = GradelyWatchSyncCodec.remainingLessonsToday(
                    from: model.timetable,
                    now: context.date
                )
                content(remaining: remaining, now: context.date)
            }
            .navigationDestination(isPresented: $showingRemaining) {
                RemainingDayView(lessons: remainingToShow)
            }
        }
    }

    @ViewBuilder
    private func content(remaining: [GradelyWatchTimetableLesson], now: Date) -> some View {
        if let lesson = remaining.first {
            Button {
                remainingToShow = remaining
                showingRemaining = true
            } label: {
                UpcomingLessonHero(lesson: lesson, remainingCount: remaining.count, now: now)
            }
            .buttonStyle(.plain)
        } else {
            WatchStatusPage(
                systemImage: "calendar.badge.checkmark",
                title: String(localized: "watch.noMoreLessons.title"),
                detail: String(localized: "watch.noMoreLessons.detail")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct UpcomingLessonHero: View {
    let lesson: GradelyWatchTimetableLesson
    let remainingCount: Int
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("watch.next")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(lesson.title)
                .font(.largeTitle.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(lesson.detailTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(WatchLessonFormatting.time(lesson.startDate))
                .font(.title3.weight(.bold))

            if let start = lesson.startDate {
                Text(WatchLessonFormatting.remaining(until: start, now: now))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WatchBrand.primary)
            }

            HStack(spacing: 8) {
                if let room = lesson.room {
                    metaChip("door.left.hand.open", room)
                }
                if let teacher = lesson.teacher {
                    metaChip("person.fill", teacher)
                }
                if let change = lesson.changeKind.shortTitle {
                    Text(LocalizedStringKey(change))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundStyle(lesson.changeKind.color)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(lesson.changeKind.color.opacity(0.8), lineWidth: 1)
                        )
                }
            }

            Spacer(minLength: 0)

            Text(
                remainingCount == 1
                    ? String(localized: "watch.remaining.tapDetails")
                    : String(format: String(localized: "watch.remaining.tapCount"), remainingCount)
            )
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 2)
    }

    private func metaChip(_ systemImage: String, _ text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct RemainingDayView: View {
    let lessons: [GradelyWatchTimetableLesson]

    var body: some View {
        List(lessons) { lesson in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(lesson.title)
                        .font(.headline.weight(.bold))
                    Spacer()
                    Text(WatchLessonFormatting.time(lesson.startDate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let room = lesson.room {
                    Text(room)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("watch.today")
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(for: .navigation) {
            WatchBrand.screenBackground
        }
    }
}
