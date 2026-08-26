import GradelyWatchShared
import SwiftUI
import WidgetKit

@main
struct GradelyWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        NextLessonComplication()
    }
}

struct NextLessonEntry: TimelineEntry {
    let date: Date
    let nowNext: GradelyWatchNowNext
}

struct NextLessonProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextLessonEntry {
        NextLessonEntry(date: Date(), nowNext: loadNowNext(at: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextLessonEntry) -> Void) {
        completion(NextLessonEntry(date: Date(), nowNext: loadNowNext(at: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextLessonEntry>) -> Void) {
        let now = Date()
        let timetable = loadTimetable()

        // Refresh the complication at every lesson boundary in the next 24 hours.
        var boundaries: Set<Date> = []
        if let timetable {
            for lesson in timetable.days.flatMap(\.lessons) {
                for date in [lesson.startDate, lesson.endDate].compactMap({ $0 }) {
                    let boundary = date.addingTimeInterval(1)
                    if boundary > now, boundary < now.addingTimeInterval(24 * 60 * 60) {
                        boundaries.insert(boundary)
                    }
                }
            }
        }

        let entryDates = [now] + boundaries.sorted()
        let entries = entryDates.map { date in
            NextLessonEntry(date: date, nowNext: GradelyWatchSyncCodec.nowAndNext(from: timetable, now: date))
        }

        let refresh = entryDates.last.map { $0.addingTimeInterval(15 * 60) } ?? now.addingTimeInterval(60 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func loadTimetable() -> GradelyWatchTimetable? {
        let url = GradelyWatchAppGroup.timetableCacheURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? GradelyWatchSyncCodec.decoder.decode(GradelyWatchTimetable.self, from: data)
    }

    private func loadNowNext(at date: Date) -> GradelyWatchNowNext {
        GradelyWatchSyncCodec.nowAndNext(from: loadTimetable(), now: date)
    }
}

struct NextLessonComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GradelyWatchNextLesson", provider: NextLessonProvider()) { entry in
            NextLessonComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("watch.complication.name")
        .description("watch.complication.description")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct NextLessonComplicationView: View {
    @Environment(\.widgetFamily) private var family

    let entry: NextLessonEntry

    private var displayed: (label: String, lesson: GradelyWatchTimetableLesson)? {
        if let current = entry.nowNext.current {
            return (String(localized: "watch.complication.now"), current)
        }
        if let next = entry.nowNext.next {
            return (String(localized: "watch.complication.next"), next)
        }
        return nil
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryRectangular:
            rectangular
        case .accessoryCorner:
            corner
        default:
            circular
        }
    }

    private var inline: some View {
        Group {
            if let displayed {
                if let timeRange = displayed.lesson.timeRange {
                    Text("\(displayed.label): \(displayed.lesson.title) \(timeRange)")
                } else {
                    Text("\(displayed.label): \(displayed.lesson.title)")
                }
            } else {
                Text("watch.complication.noLessons")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let displayed {
                let accent = displayed.lesson.changeKind.color
                HStack(spacing: 4) {
                    Text(displayed.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(displayed.lesson.changeKind == .none ? Color.accentColor : accent)
                    if let change = displayed.lesson.changeKind.shortTitle {
                        Text(LocalizedStringKey(change))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
                Text(displayed.lesson.detailTitle)
                    .font(.headline)
                    .strikethrough(displayed.lesson.isCanceled)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let timeRange = displayed.lesson.timeRange {
                        Text(timeRange)
                    }
                    if let room = displayed.lesson.room {
                        Text(room)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("watch.complication.noLessons")
                    .font(.headline)
                Text("watch.complication.freeTime")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let displayed {
                VStack(spacing: 0) {
                    Text(displayed.lesson.title)
                        .font(.headline.weight(.bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .strikethrough(displayed.lesson.isCanceled)
                        .foregroundStyle(displayed.lesson.changeKind == .none ? .primary : displayed.lesson.changeKind.color)
                    if let start = displayed.lesson.startDate {
                        Text(start, style: .time)
                            .font(.caption2)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(2)
            } else {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title3)
            }
        }
    }

    private var corner: some View {
        Group {
            if let displayed {
                Text(displayed.lesson.title)
                    .font(.headline.weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(displayed.lesson.changeKind == .none ? .primary : displayed.lesson.changeKind.color)
                    .widgetLabel {
                        if let timeRange = displayed.lesson.timeRange {
                            Text("\(displayed.label) \(timeRange)")
                        } else {
                            Text(displayed.label)
                        }
                    }
            } else {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title3)
                    .widgetLabel("watch.complication.noLessons")
            }
        }
    }
}
