import SwiftUI

@main
struct PadelWatchApp: App {
    @State private var store = WatchMatchStore()

    var body: some Scene {
        WindowGroup {
            WatchScoreboardView()
                .environment(store)
        }
    }
}
