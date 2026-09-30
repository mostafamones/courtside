import SwiftUI

struct PlayersView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Player?
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.sortedPlayers) { player in
                    NavigationLink(value: player.id) {
                        VStack(alignment: .leading) {
                            Text(player.displayName).font(.headline)
                            if player.nickname?.nilIfBlank != nil {
                                Text(player.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.deletePlayer(player) }
                        Button("Edit") { editing = player }
                    }
                }
            }
            .overlay {
                if store.players.isEmpty {
                    ContentUnavailableView("No players", systemImage: "person.2",
                                           description: Text("Add the people you play with. No account needed."))
                }
            }
            .navigationTitle("Players")
            .toolbar {
                Button("Add player", systemImage: "plus") { isAdding = true }
            }
            .navigationDestination(for: UUID.self) { id in
                PlayerDetailView(playerID: id, editing: $editing)
            }
            .sheet(isPresented: $isAdding) {
                PlayerEditor(player: nil)
            }
            .sheet(item: $editing) { player in
                PlayerEditor(player: player)
            }
        }
    }
}

struct PlayerDetailView: View {
    @Environment(AppStore.self) private var store
    let playerID: UUID
    @Binding var editing: Player?

    var body: some View {
        if let player = store.player(id: playerID) {
            let matches = store.matches(for: player)
            let wins = matches.filter { record in
                guard let winner = record.state.winner,
                      let index = record.setup.players.firstIndex(where: { $0.id == player.id }) else { return false }
                return MatchSetup.team(of: index) == winner
            }.count
            List {
                Section {
                    LabeledContent("Name", value: player.name)
                    if let nickname = player.nickname?.nilIfBlank {
                        LabeledContent("Nickname", value: nickname)
                    }
                    LabeledContent("Matches", value: "\(matches.count)")
                    LabeledContent("Wins", value: "\(wins)")
                }
                Section("Match history") {
                    ForEach(matches) { MatchSummaryRow(record: $0) }
                }
            }
            .navigationTitle(player.displayName)
            .toolbar { Button("Edit") { editing = player } }
        } else {
            ContentUnavailableView("Player deleted", systemImage: "person.slash")
        }
    }
}

struct PlayerEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let player: Player?
    @State private var name = ""
    @State private var nickname = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Nickname (optional)", text: $nickname)
            }
            .navigationTitle(player == nil ? "New player" : "Edit player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if var player {
                            player.name = name.trimmingCharacters(in: .whitespaces)
                            player.nickname = nickname.nilIfBlank
                            store.updatePlayer(player)
                        } else {
                            store.addPlayer(name: name, nickname: nickname)
                        }
                        dismiss()
                    }
                    .disabled(name.nilIfBlank == nil)
                }
            }
            .onAppear {
                name = player?.name ?? ""
                nickname = player?.nickname ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}
