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

                    NavigationStack {
                        TodayLessonsView(model: model)
                    }

                    if model.isRecurringSupporter {
                        NavigationStack {
                            GradeyAIWatchView(model: model)
                        }
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
    }

    private var signedOutView: some View {
        WatchStatusPage(
            systemImage: "iphone.and.arrow.forward",
            title: String(localized: "watch.signedOut.title"),
            detail: String(localized: "watch.signedOut.detail")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
