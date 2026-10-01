import SwiftUI

/// Two stacked halves: team A on top, team B on the bottom (or swapped via "Switch sides").
/// Tap a half to add a point, double tap to remove one, long press for more.
struct WatchScoreboardView: View {
    @Environment(WatchMatchStore.self) private var store
    @State private var feedback = 0
    @State private var showMenu = false
    @State private var showFavourites = false

    var body: some View {
        if let record = store.record {
            scoreboard(record)
        } else {
            WatchWaitingView()
        }
    }

    private func scoreboard(_ record: MatchRecord) -> some View {
        let state = record.state
        return ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                let top: TeamSide = store.flipped ? .b : .a
                WatchTeamHalf(record: record, state: state, team: top, isTop: true, onAction: apply)
                Rectangle().fill(Color(white: 0.2)).frame(height: 1)
                WatchTeamHalf(record: record, state: state, team: top.opponent, isTop: false, onAction: apply)
            }
            .ignoresSafeArea()

            if state.isFinished {
                WatchMatchCompleteCard(record: record, state: state,
                                       onUndo: store.undo, onNewMatch: { showFavourites = true })
            } else if let winner = state.pendingGameWinner {
                WatchConfirmGameCard(record: record, winner: winner,
                                     onConfirm: { apply(.confirmGame) }, onUndo: store.undo)
            } else if state.needsGoldenPointSide {
                WatchGoldenPointPicker { apply(.chooseGoldenPointSide($0)) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFavourites) {
            WatchFavouritesList { showFavourites = false }
        }
        .onLongPressGesture { showMenu = true }
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .confirmationDialog("Match", isPresented: $showMenu) {
            Button("Undo last action") { store.undo() }.disabled(!store.canUndo)
            Button("Switch sides") { store.flipped.toggle() }
        }
    }

    private func apply(_ action: MatchAction) {
        if store.apply(action) { feedback += 1 }
    }
}

struct WatchTeamHalf: View {
    let record: MatchRecord
    let state: MatchState
    let team: TeamSide
    let isTop: Bool
    let onAction: (MatchAction) -> Void

    var body: some View {
        // Top half: accessory above the score. Bottom half: accessory below it.
        // The accessory is the server's name for the serving team, otherwise the game label.
        // Accessories are pinned to the outer edges (the top one lines up with the system
        // clock) while the scores are pushed toward the middle divider.
        VStack(spacing: 0) {
            if isTop {
                topAccessory.frame(height: 20).padding(.top, 18)
                Spacer(minLength: 0)
                scoreRow.padding(.bottom, 8)
            } else {
                scoreRow.padding(.top, 8)
                Spacer(minLength: 0)
                bottomAccessory.frame(height: 20).padding(.bottom, 18)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Double tap must win over single tap, so a removal never also adds a point.
        .gesture(
            TapGesture(count: 2).onEnded { onAction(.removePoint(team)) }
                .exclusively(before: TapGesture(count: 1).onEnded { onAction(.point(team)) })
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.setup.teamName(team))
        .accessibilityAction(named: "Add point") { onAction(.point(team)) }
        .accessibilityAction(named: "Remove point") { onAction(.removePoint(team)) }
    }

    private var isServing: Bool { state.servingTeam == team && !state.isFinished }

    /// Top: the server's name when team A serves, otherwise the game label.
    @ViewBuilder
    private var topAccessory: some View {
        if isServing {
            serverName.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            gameLabel.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Bottom: the server's name when team B serves, otherwise the game label.
    @ViewBuilder
    private var bottomAccessory: some View {
        if isServing {
            serverName.frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            gameLabel.frame(maxWidth: .infinity)
        }
    }

    private var scoreRow: some View {
        // Score is dead-centre; the games count sits on the leading edge, vertically centred with it.
        ZStack {
            let font = Font.system(size: 52, weight: .heavy, design: .rounded)
            Text("00").font(font).hidden()
                .overlay {
                    Text(state.pointLabel(for: team))
                        .font(font)
                        .foregroundStyle(record.setup.colors[team].color)
                        .minimumScaleFactor(0.2)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(state.pointLabel(for: team)) points")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            Text("\(state.games[team])")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(state.games[team]) games")
        }
        .animation(.snappy, value: state.points)
    }

    private var gameLabel: some View {
        Text(state.statusLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(white: 0.6))
    }

    /// Name stays put; the ball sits on the left or right of it to show the
    /// side the server is serving from (server's perspective).
    private var serverName: some View {
        let name = record.setup.players[state.server].name.uppercased()
        let ball = Circle().fill(Color(red: 0.45, green: 0.95, blue: 0.1))
            .frame(width: 10, height: 10)
        let label = Text(name)
            .font(.system(size: 14, weight: .semibold))
            .tracking(-0.5)
            .foregroundStyle(.white)
            .lineLimit(1)
        // The group hugs its side of the screen; the ball sits left or right of the name,
        // vertically centred with it.
        return HStack(alignment: .center, spacing: 4) {
            if state.serveSide == .left {
                ball
                label
            } else {
                label
                ball
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) serving from the \(state.serveSide.rawValue)")
    }
}

// MARK: - Waiting

struct WatchWaitingView: View {
    @Environment(WatchMatchStore.self) private var store

    var body: some View {
        if store.favourites.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 34))
                    .foregroundStyle(Color(red: 0.45, green: 0.95, blue: 0.1))
                Text("Start a match on your iPhone to start tracking the score")
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        } else {
            WatchFavouritesList()
        }
    }
}

/// Starts a match from one of the phone's favourites.
struct WatchFavouritesList: View {
    @Environment(WatchMatchStore.self) private var store
    var onStart: () -> Void = {}

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.favourites) { favourite in
                    Button {
                        store.start(favourite)
                        onStart()
                    } label: {
                        HStack(spacing: 10) {
                            Text(favourite.emoji).font(.body)
                            Text(favourite.name).font(.headline).lineLimit(1)
                        }
                        .padding(.vertical, 6)
                    }
                }
                Text("Or start a match on your iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("New match")
            .padding(.top, 4)
        }
    }
}

// MARK: - Overlays

struct WatchConfirmGameCard: View {
    let record: MatchRecord
    let winner: TeamSide
    let onConfirm: () -> Void
    let onUndo: () -> Void

    var body: some View {
        let color = record.setup.colors[winner].color
        VStack(spacing: 8) {
            Text(record.setup.teamName(winner))
                .font(.headline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 8) {
                Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                    .accessibilityLabel("Undo")
                Button(action: onConfirm) { Image(systemName: "checkmark").fontWeight(.bold) }
                    .tint(color)
                    .foregroundStyle(.black)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Confirm")
            }
        }
        .padding(12)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 8)
    }
}

struct WatchGoldenPointPicker: View {
    let onChoose: (CourtSide) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("Golden point · receivers choose")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Left") { onChoose(.left) }
                Button("Right") { onChoose(.right) }
            }
        }
        .padding(10)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 8)
    }
}

struct WatchMatchCompleteCard: View {
    @Environment(WatchMatchStore.self) private var store
    let record: MatchRecord
    let state: MatchState
    let onUndo: () -> Void
    let onNewMatch: () -> Void

    var body: some View {
        let winner = state.winner ?? .a
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(record.setup.colors[winner].color)
                Text("\(record.setup.teamName(winner)) win")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(record.setResultsText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                if store.favourites.isEmpty {
                    Text("Start a new match on your iPhone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Button("New match", systemImage: "plus", action: onNewMatch)
                }
                Button("Home", systemImage: "house", action: store.close)
            }
            .padding(10)
        }
        .background(Color(white: 0.08))
    }
}

extension MatchRecord {
    /// e.g. "6–4  3–6  [10–7]"
    var setResultsText: String {
        state.completedSets.map { set in
            if set.isMatchTiebreak, let tb = set.tiebreak { return "[\(tb.a)–\(tb.b)]" }
            if let tb = set.tiebreak { return "\(set.games.a)–\(set.games.b) (\(min(tb.a, tb.b)))" }
            return "\(set.games.a)–\(set.games.b)"
        }
        .joined(separator: "   ")
    }
}
