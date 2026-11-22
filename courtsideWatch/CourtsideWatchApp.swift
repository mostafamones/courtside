import SwiftUI

@main
struct CourtsideWatchApp: App {
    @State private var store = WatchMatchStore()

    var body: some Scene {
        WindowGroup {
            WatchScoreboardView()
                .environment(store)
        }
    }
}
