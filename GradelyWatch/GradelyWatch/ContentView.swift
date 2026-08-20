import GradelyWatchShared
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: WatchAppModel

    var body: some View {
        Group {
            if model.isSignedIn {
                TabView {
                    NavigationStack {
                        CurrentLessonView(model: model)
                    }
                    UpcomingLessonView(model: model)
                    NavigationStack {
                        GradeyAIWatchView(model: model)
                    }
                }
                .tabViewStyle(.verticalPage)
                .containerBackground(for: .tabView) {
                    WatchBrand.screenBackground
                }
            } else {
                signedOutView
                    .containerBackground(for: .navigation) {
                        WatchBrand.screenBackground
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            refreshButton
        }
    }

    private var signedOutView: some View {
        WatchStatusPage(
            systemImage: "iphone.and.arrow.forward",
            title: "Open Gradey on iPhone",
            detail: "Sign in and the watch will receive your school session."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refreshTimetable() }
        } label: {
            Group {
                if model.isSyncing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(width: 26, height: 26)
            .background(.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.isSignedIn || model.isSyncing)
        .padding(.leading, 2)
        .padding(.top, 1)
    }
}
