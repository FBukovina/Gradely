import SwiftUI

@main
struct GradelyWatchApp: App {
    @StateObject private var model = WatchAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
                    await model.start()
                }
        }
    }
}
