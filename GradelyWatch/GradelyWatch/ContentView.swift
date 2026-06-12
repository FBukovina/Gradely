import GradelyWatchShared
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: WatchAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    if !model.isSignedIn {
                        signedOutView
                    } else {
                        lessonCards
                    }

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
            }
            .navigationTitle("Gradey")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refreshTimetable() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!model.isSignedIn || model.isSyncing)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let schoolName = model.user?.schoolName {
                Text(schoolName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(model.statusTitle)
                    .font(.headline.weight(.bold))
                    .lineLimit(2)

                if model.isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
    }

    private var signedOutView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2.weight(.semibold))
            Text("Open Gradey on iPhone and sign in.")
                .font(.body.weight(.semibold))
            Text("The watch will receive your Bakalari session from the phone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var lessonCards: some View {
        let nowNext = model.nowAndNext

        if nowNext.isEmpty {
            switch model.lessonSelection {
            case .noTimetable:
                emptyState("No timetable yet", systemImage: "calendar")
            case .stale:
                emptyState("Open Gradey to refresh", systemImage: "arrow.clockwise")
            default:
                emptyState("No more lessons", systemImage: "calendar.badge.checkmark")
            }
        } else {
            if let current = nowNext.current {
                LessonCard(label: "Now", lesson: current)
            }
            if let next = nowNext.next {
                LessonCard(label: "Next", lesson: next)
            }
        }
    }

    private func emptyState(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LessonCard: View {
    let label: String
    let lesson: GradelyWatchTimetableLesson

    private var accent: Color {
        lesson.changeKind.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(lesson.detailTitle)
                .font(.title3.weight(.heavy))
                .lineLimit(2)
                .strikethrough(lesson.isCanceled)
                .foregroundStyle(lesson.changeKind == .none ? .primary : accent)

            VStack(alignment: .leading, spacing: 3) {
                if let timeRange = lesson.timeRange {
                    Label(timeRange, systemImage: "clock")
                }
                if let room = lesson.room {
                    Label(room, systemImage: "door.left.hand.open")
                }
                if let change = lesson.changeKind.shortTitle {
                    Label(change, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(accent)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(lesson.changeKind == .none ? .clear : accent.opacity(0.55), lineWidth: 1.5)
        )
    }
}
