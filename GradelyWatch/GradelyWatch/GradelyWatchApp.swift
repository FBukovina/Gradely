import GradelyWatchShared
import SwiftUI

@main
struct GradelyWatchApp: App {
    @StateObject private var model = WatchAppModel()

    init() {
        GradelyWatchFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .font(.gradely(.body))
                .task {
                    await model.start()
                }
        }
    }
}
