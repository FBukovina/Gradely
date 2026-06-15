import SwiftUI
import WidgetKit
#if os(macOS)
import AppKit
#endif

@main
struct GradelyWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
    }
}

struct NextLessonWidget: Widget {
    var body: some WidgetConfiguration {
        #if os(macOS)
        configuration
            .supportedFamilies([.systemSmall, .systemMedium])
        #else
        configuration
            .supportedFamilies([.accessoryRectangular])
        #endif
    }

    private var configuration: some WidgetConfiguration {
        StaticConfiguration(
            kind: NextLessonWidgetConstants.widgetKind,
            provider: NextLessonProvider()
        ) { entry in
            NextLessonWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GradelyWidgetBackground()
                }
                .widgetURL(NextLessonWidgetConstants.timetableDeepLink)
        }
        .configurationDisplayName("Next Lesson")
        .description(configurationDescription)
    }

    private var configurationDescription: String {
        #if os(macOS)
        return "See your current or next subject on the desktop."
        #else
        return "See your current or next subject on the Lock Screen."
        #endif
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

    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        #if os(macOS)
        systemBody
        #else
        accessoryBody
        #endif
    }

    @ViewBuilder
    private var accessoryBody: some View {
        switch entry.selection {
        case .lesson(let lesson, let timing):
            accessoryLessonView(lesson: lesson, timing: timing)
        case .noSnapshot:
            accessoryEmptyView(title: "Open Gradey", subtitle: "Load timetable", systemImage: "calendar")
        case .noLessons:
            accessoryEmptyView(title: "No lessons", subtitle: "Open Gradey", systemImage: "calendar.badge.checkmark")
        case .stale:
            accessoryEmptyView(title: "Open Gradey", subtitle: "Refresh timetable", systemImage: "arrow.clockwise")
        }
    }

    @ViewBuilder
    private var systemBody: some View {
        switch entry.selection {
        case .lesson(let lesson, let timing):
            systemLessonView(lesson: lesson, timing: timing)
        case .noSnapshot:
            systemEmptyView(title: "Open Gradey", subtitle: "Load your timetable to show the next lesson.", systemImage: "calendar")
        case .noLessons:
            systemEmptyView(title: "No lessons", subtitle: "Your timetable is clear for now.", systemImage: "calendar.badge.checkmark")
        case .stale:
            systemEmptyView(title: "Refresh timetable", subtitle: "Open Gradey to update this widget.", systemImage: "arrow.clockwise")
        }
    }

    private func accessoryLessonView(lesson: NextLessonWidgetLesson, timing: NextLessonWidgetTiming) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let statusLine = statusLine(for: lesson, timing: timing) {
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
        .gradelyWidgetAccentable()
    }

    private func accessoryEmptyView(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .lineLimit(1)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .gradelyWidgetAccentable()
    }

    private func systemLessonView(
        lesson: NextLessonWidgetLesson,
        timing: NextLessonWidgetTiming
    ) -> some View {
        VStack(alignment: .leading, spacing: widgetFamily == .systemMedium ? 10 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(timingText(for: timing), systemImage: timing == .current ? "clock.fill" : "clock")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let changeText = changeText(for: lesson.changeKind) {
                    Text(changeText)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundStyle(changeColor(for: lesson.changeKind))
                        .background(changeColor(for: lesson.changeKind).opacity(0.16), in: Capsule())
                }
            }

            Text(lesson.detailTitle)
                .font(widgetFamily == .systemMedium ? .title3.weight(.heavy) : .headline.weight(.heavy))
                .lineLimit(widgetFamily == .systemMedium ? 2 : 1)
                .minimumScaleFactor(0.75)

            if widgetFamily == .systemMedium, let teacher = trimmed(lesson.teacher) {
                Label(teacher, systemImage: "person")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let timeRange = trimmed(lesson.timeRange) {
                    metadataLabel(timeRange, systemImage: "calendar")
                }

                if let room = trimmed(lesson.room) {
                    metadataLabel(room, systemImage: "door.left.hand.open")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func systemEmptyView(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.heavy))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(widgetFamily == .systemMedium ? 2 : 1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func statusLine(for lesson: NextLessonWidgetLesson, timing: NextLessonWidgetTiming) -> String? {
        let timeRange = lesson.timeRange?.trimmingCharacters(in: .whitespacesAndNewlines)
        let changeText = changeText(for: lesson.changeKind)
        let timingText = timingText(for: timing)

        return [timingText, timeRange?.isEmpty == false ? timeRange : nil, changeText]
            .compactMap { $0 }
            .joined(separator: " - ")
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

    private func changeColor(for changeKind: NextLessonWidgetChangeKind) -> Color {
        switch changeKind {
        case .none:
            return .secondary
        case .canceled:
            return .red
        case .substitution, .roomChanged:
            return .orange
        case .added:
            return .green
        }
    }

    private func timingText(for timing: NextLessonWidgetTiming) -> String {
        switch timing {
        case .current:
            return "Now"
        case .upcoming:
            return "Next"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct GradelyWidgetBackground: View {
    var body: some View {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        AccessoryWidgetBackground()
        #endif
    }
}

private extension View {
    @ViewBuilder
    func gradelyWidgetAccentable() -> some View {
        #if os(macOS)
        self
        #else
        self.widgetAccentable()
        #endif
    }
}

#if os(macOS)
#Preview(as: .systemSmall) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry(date: Date(), selection: .lesson(NextLessonProvider.previewLesson, timing: .upcoming))
}

#Preview(as: .systemMedium) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry(date: Date(), selection: .lesson(NextLessonProvider.previewLesson, timing: .upcoming))
}
#else
#Preview(as: .accessoryRectangular) {
    NextLessonWidget()
} timeline: {
    NextLessonEntry(date: Date(), selection: .lesson(NextLessonProvider.previewLesson, timing: .upcoming))
}
#endif
