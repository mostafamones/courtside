import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Binding var setupRequest: SetupRequest?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.history) { record in
                    NavigationLink(value: record.id) { MatchSummaryRow(record: record) }
                        .swipeActions {
                            Button("Delete", role: .destructive) { store.deleteMatch(record) }
                        }
                }
            }
            .overlay {
                if store.history.isEmpty {
                    ContentUnavailableView("No matches yet", systemImage: "clock",
                                           description: Text("Completed and ended-early matches appear here."))
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in
                MatchDetailView(matchID: id, setupRequest: $setupRequest)
            }
        }
    }
}

struct MatchDetailView: View {
    @Environment(AppStore.self) private var store
    let matchID: UUID
    @Binding var setupRequest: SetupRequest?

    var body: some View {
        if let record = store.match(id: matchID) {
            let state = record.state
            List {
                Section {
                    HStack {
                        StatusBadge(status: record.status)
                        Spacer()
                        Text(record.startedAt, format: .dateTime.weekday().day().month().year().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    if let preset = record.presetName {
                        LabeledContent("Preset", value: preset)
                    }
                }

                Section("Result") {
                    ForEach(TeamSide.allCases, id: \.self) { team in
                        HStack {
                            TeamLine(setup: record.setup, team: team)
                                .fontWeight(state.winner == team ? .bold : .regular)
                            if state.winner == team {
                                Image(systemName: "trophy.fill").foregroundStyle(record.setup.colors[team].color)
                            }
                            Spacer()
                            SetScoresText(record: record, team: team)
                        }
                    }
                    if !state.completedSets.isEmpty {
                        ForEach(Array(state.completedSets.enumerated()), id: \.offset) { index, set in
                            LabeledContent(set.isMatchTiebreak ? "Match tiebreak" : "Set \(index + 1)") {
                                Text(setText(set)).monospacedDigit()
                            }
                        }
                    }
                    if record.status == .endedEarly, state.games != .zero || state.points != .zero {
                        LabeledContent("When ended") {
                            Text("\(state.games.a)–\(state.games.b) in games, \(state.pointLabel(for: .a))–\(state.pointLabel(for: .b))")
                        }
                    }
                }

                Section("Stats") {
                    LabeledContent("Duration", value: Duration.seconds(record.duration)
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    ForEach(TeamSide.allCases, id: \.self) { team in
                        LabeledContent("Points won · \(record.setup.teamName(team))", value: "\(state.pointsWon[team])")
                    }
                }

                Section("Rules") {
                    LabeledContent("Match length", value: record.setup.rules.matchLengthTitle)
                    LabeledContent("Deuce", value: record.setup.rules.deuceRule.title)
                    LabeledContent("Games per set", value: "\(record.setup.rules.gamesPerSet)")
                    LabeledContent("Tiebreak", value: "To \(record.setup.rules.tiebreakTarget) at \(record.setup.rules.gamesPerSet)–\(record.setup.rules.gamesPerSet)")
                    if record.setup.rules.setsToWin > 1 {
                        LabeledContent("Deciding set", value: record.setup.rules.decidingSet.title)
                    }
                }

                Section {
                    Button("Play again", systemImage: "arrow.clockwise") {
                        setupRequest = .newMatch(record.setup, presetName: record.presetName)
                    }
                }
            }
            .navigationTitle("Match")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Match deleted", systemImage: "trash")
        }
    }

    private func setText(_ set: SetResult) -> String {
        if set.isMatchTiebreak, let tb = set.tiebreak { return "\(tb.a)–\(tb.b)" }
        if let tb = set.tiebreak { return "\(set.games.a)–\(set.games.b)  (\(tb.a)–\(tb.b))" }
        return "\(set.games.a)–\(set.games.b)"
    }
}
