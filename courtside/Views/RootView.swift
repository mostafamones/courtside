import SwiftUI

/// Identifies what the app is presenting full screen / as a sheet.
enum SetupRequest: Identifiable {
    case newMatch(MatchSetup?, presetName: String?)
    case editFavourite(Favourite)

    var id: String {
        switch self {
        case .newMatch: "new"
        case .editFavourite(let favourite): favourite.id.uuidString
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var showScoreboard = false
    @State private var setupRequest: SetupRequest?

    var body: some View {
        TabView {
            Tab("Play", systemImage: "figure.tennis") {
                PlayView(showScoreboard: $showScoreboard, setupRequest: $setupRequest)
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                HistoryView(setupRequest: $setupRequest)
            }
            Tab("Players", systemImage: "person.2") {
                PlayersView()
            }
        }
        .sheet(item: $setupRequest) { request in
            MatchSetupView(request: request) { setup, favouriteName in
                store.startMatch(setup, presetName: favouriteName)
                setupRequest = nil
                showScoreboard = true
            }
        }
        .fullScreenCover(isPresented: $showScoreboard) {
            ScoreboardView(setupRequest: $setupRequest, isPresented: $showScoreboard)
        }
    }
}
