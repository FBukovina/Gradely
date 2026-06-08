import SwiftUI
import WidgetKit

@main
struct GradelyWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
    }
}

struct NextLessonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: NextLessonWidgetConstants.widgetKind,
            provider: NextLessonProvider()
        ) { entry in
            NextLessonWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    AccessoryWidgetBackground()
                }
                .widgetURL(NextLessonWidgetConstants.timetableDeepLink)
        }
        .configurationDisplayName("Next Lesson")
        .description("See your current or next subject on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct NextLessonEntry: TimelineEntry {
    let date: Date
    let selection: NextLessonWidgetSelection
}

struct NextLessonProvider: TimelineProvider {
    private let store: (any NextLessonWidgetStoring)?
    private let calendar: Calendar

    init(
        store: (any NextLessonWidgetStoring)? = NextLessonWidgetStore(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.calendar = calendar
    }

    func placeholder(in context: Context) -> NextLessonEntry {
        NextLessonEntry(date: Date(), selection: .lesson(Self.previewLesson, timing: .upcoming))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextLessonEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }

        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextLessonEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let now = Date()
        let updateDates = NextLessonSelector.timelineDates(snapshot: snapshot, after: now)
            .map { $0.addingTimeInterval(1) }
        let entryDates = [now] + updateDates
        let entries = entryDates.map { date in
            NextLessonEntry(
                date: date,
                selection: NextLessonSelector.select(snapshot: snapshot, now: date)
            )
        }
        let fallbackRefresh = calendar.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(30 * 60)
        let policy: TimelineReloadPolicy = entries.count > 1 ? .atEnd : .after(fallbackRefresh)

        completion(Timeline(entries: entries, policy: policy))
    }

    private func entry(for date: Date) -> NextLessonEntry {
        NextLessonEntry(date: date, selection: NextLessonSelector.select(snapshot: loadSnapshot(), now: date))
    }

    private func loadSnapshot() -> NextLessonWidgetSnapshot? {
        try? store?.loadSnapshot()
    }

    fileprivate static var previewLesson: NextLessonWidgetLesson {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let startDate = calendar.date(bySettingHour: 8, minute: 55, second: 0, of: dayStart)
        let endDate = calendar.date(bySettingHour: 9, minute: 40, second: 0, of: dayStart)

        return NextLessonWidgetLesson(
            id: "preview-math",
            dayStart: dayStart,
            startDate: startDate,
            endDate: endDate,
            subjectName: "Mathematics",
            subjectAbbrev: "M",
            timeRange: "08:55-09:40",
            room: "12",
            teacher: nil,
            changeKind: .none
        )
    }
}

private struct NextLessonWidgetView: View {
    let entry: NextLessonEntry

    var body: some View {
        switch entry.selection {
        case .lesson(let lesson, _):
            lessonView(lesson: lesson)
        case .noSnapshot:
            emptyView(title: "Open Gradely", subtitle: "Load timetable", systemImage: "calendar")
        case .noLessons:
            emptyView(title: "No lessons", subtitle: "Open Gradely", systemImage: "calendar.badge.checkmark")
        case .stale:
            emptyView(title: "Open Gradely", subtitle: "Refresh timetable", systemImage: "arrow.clockwise")
        }
    }

    private func lessonView(lesson: NextLessonWidgetLesson) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let statusLine = statusLine(for: lesson) {
                Text(statusLine)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .lineLimit(1)
            }

            Text(lesson.title)
                .font(.headline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let room = lesson.room {
                Label(room, systemImage: "door.left.hand.open")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    private func emptyView(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .lineLimit(1)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    private func statusLine(for lesson: NextLessonWidgetLesson) -> String? {
        let timeRange = lesson.timeRange?.trimmingCharacters(in: .whitespacesAndNewlines)
        let changeText = changeText(for: lesson.changeKind)

        switch (timeRange?.isEmpty == false ? timeRange : nil, changeText) {
        case (.some(let timeRange), .some(let changeText)):
            return "\(timeRange) - \(changeText)"
        case (.some(let timeRange), nil):
            return timeRange
        case (nil, .some(let changeText)):
            return changeText
        case (nil, nil):
            return nil
        }
    }

    private func changeText(for changeKind: NextLessonWidgetChangeKind) -> String? {
        switch changeKind {
        case .none:
            return nil
        case .canceled:
            return "Canceled"
        case .substitution:
            return "Changed"
        case .roomChanged:
            return "Room"
        case .added:
            return "Added"
        }
    }
}

#Preview(as: .accessoryRectangular) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry(date: Date(), selection: .lesson(NextLessonProvider.previewLesson, timing: .upcoming))
}
