import SwiftUI

/// Courtside landscape scoreboard: two large side-by-side team areas.
/// Tap a team's area to add a point, double tap to remove one.
struct ScoreboardView: View {
    @Environment(AppStore.self) private var store
    @Binding var setupRequest: SetupRequest?
    @Binding var isPresented: Bool
    @State private var feedback = 0
    @State private var confirmEndEarly = false

    /// The active match, or the match that was just completed (so the result and undo stay reachable).
    private var record: MatchRecord? {
        store.activeMatch ?? store.matches.last.flatMap { $0.status == .completed ? $0 : nil }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let record {
                let state = record.state
                HStack(spacing: 0) {
                    TeamPanel(record: record, state: state, team: .a)
                    Rectangle().fill(Color(white: 0.18)).frame(width: 1).padding(.top, 64).padding(.bottom, 24)
                    TeamPanel(record: record, state: state, team: .b)
                }
                .overlay(alignment: .top) { topBar(state: state) }
                .overlay(alignment: .bottom) {
                    if state.needsGoldenPointSide {
                        GoldenPointPicker(receivers: record.setup.teamName(state.servingTeam.opponent)) {
                            store.apply(.chooseGoldenPointSide($0))
                        }
                        .padding(.bottom, 64)
                    }
                }
                .overlay {
                    if state.isFinished {
                        MatchCompleteCard(record: record, state: state,
                                          onUndo: { store.undo() },
                                          onPlayAgain: playAgain,
                                          onDone: { isPresented = false })
                    } else if let winner = state.pendingGameWinner {
                        ConfirmGameCard(record: record, state: state, winner: winner,
                                        onConfirm: { if store.apply(.confirmGame) { feedback += 1 } },
                                        onUndo: { store.undo() })
                    }
                }
            } else {
                Color.clear.onAppear { isPresented = false }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .confirmationDialog("End this match early?", isPresented: $confirmEndEarly, titleVisibility: .visible) {
            Button("End match", role: .destructive) {
                store.endActiveMatchEarly()
                isPresented = false
            }
        } message: {
            Text("The score so far is saved in history as ended early.")
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            AppDelegate.lock(.landscape)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            AppDelegate.lock(.allButUpsideDown)
        }
        .environment(\.scoreAction) { action in
            if store.apply(action) { feedback += 1 }
        }
    }

    private func topBar(state: MatchState) -> some View {
        HStack {
            CircleButton(systemImage: "chevron.down", label: "Minimize") { isPresented = false }
            Spacer()
            Text(state.gameLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.5))
                .tracking(1)
            Spacer()
            CircleButton(systemImage: "arrow.uturn.backward", label: "Undo last action") { store.undo() }
                .disabled(record?.actions.isEmpty ?? true)
            if !state.isFinished {
                Menu {
                    Button("End match early", systemImage: "flag.checkered", role: .destructive) {
                        confirmEndEarly = true
                    }
                } label: {
                    CircleButtonLabel(systemImage: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func playAgain() {
        guard let record else { return }
        setupRequest = .newMatch(record.setup, presetName: record.presetName)
        isPresented = false
    }
}

// MARK: - Team panel

private struct ScoreActionKey: EnvironmentKey {
    static let defaultValue: (MatchAction) -> Void = { _ in }
}

extension EnvironmentValues {
    var scoreAction: (MatchAction) -> Void {
        get { self[ScoreActionKey.self] }
        set { self[ScoreActionKey.self] = newValue }
    }
}

struct TeamPanel: View {
    @Environment(\.scoreAction) private var scoreAction
    let record: MatchRecord
    let state: MatchState
    let team: TeamSide

    var body: some View {
        let color = record.setup.colors[team].color
        VStack(spacing: 0) {
            Spacer(minLength: 44)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text("\(state.games[team])")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
                    .accessibilityLabel("\(state.games[team]) games")
                Text(state.pointLabel(for: team))
                    .font(.system(size: state.pendingGameWinner == team ? 96 : 150, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(state.pointLabel(for: team)) points")
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: state.points)

            SetsStrip(record: record, state: state, team: team)
                .padding(.top, 4)

            Spacer(minLength: 8)
            serverRow
                .frame(height: 36)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Double tap must win over single tap, so a removal never also adds a point.
        .gesture(
            TapGesture(count: 2).onEnded { scoreAction(.removePoint(team)) }
                .exclusively(before: TapGesture(count: 1).onEnded { scoreAction(.point(team)) })
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(record.setup.teamName(team))
        .accessibilityAction(named: "Add point") { scoreAction(.point(team)) }
        .accessibilityAction(named: "Remove point") { scoreAction(.removePoint(team)) }
    }

    /// Ball + name toward the edge the server is serving from (server's perspective):
    /// left edge with ball first, or right edge with ball last.
    @ViewBuilder
    private var serverRow: some View {
        if state.servingTeam == team && !state.isFinished {
            let name = record.setup.players[state.server].name.uppercased()
            let ball = Circle().fill(Color(red: 0.45, green: 0.95, blue: 0.1)).frame(width: 14, height: 14)
            HStack(spacing: 10) {
                if state.serveSide == .left {
                    ball
                    Text(name)
                    Spacer()
                } else {
                    Spacer()
                    Text(name)
                    ball
                }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .accessibilityLabel("\(name) serving from the \(state.serveSide.rawValue)")
        } else {
            Color.clear
        }
    }
}

struct SetsStrip: View {
    let record: MatchRecord
    let state: MatchState
    let team: TeamSide

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(state.completedSets.enumerated()), id: \.offset) { _, set in
                Text(set.isMatchTiebreak ? "\(set.tiebreak?[team] ?? 0)" : "\(set.games[team])")
                    .foregroundStyle(set.winner == team ? Color(white: 0.8) : Color(white: 0.4))
            }
        }
        .font(.headline.monospacedDigit())
        .frame(height: 22)
    }
}

// MARK: - Overlays

struct ConfirmGameCard: View {
    let record: MatchRecord
    let state: MatchState
    let winner: TeamSide
    let onConfirm: () -> Void
    let onUndo: () -> Void

    private var title: String {
        switch state.gameKind {
        case .regular: "Game"
        case .tiebreak: "Tiebreak & set"
        case .matchTiebreak: "Match tiebreak"
        }
    }

    var body: some View {
        let color = record.setup.colors[winner].color
        VStack(spacing: 14) {
            Text("\(title) · \(record.setup.teamName(winner))")
                .font(.headline)
                .foregroundStyle(color)
            Text("Double tap a side to correct, or confirm to record it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(action: onUndo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                Button(action: onConfirm) {
                    Label("Confirm", systemImage: "checkmark")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .foregroundStyle(.black)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 360)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(color.opacity(0.5), lineWidth: 1))
        .shadow(radius: 30)
    }
}

struct GoldenPointPicker: View {
    let receivers: String
    let onChoose: (CourtSide) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Golden point · \(receivers) choose")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Button("Left") { onChoose(.left) }
            Button("Right") { onChoose(.right) }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.1), in: Capsule())
    }
}

struct MatchCompleteCard: View {
    let record: MatchRecord
    let state: MatchState
    let onUndo: () -> Void
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        let winner = state.winner ?? .a
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.largeTitle)
                .foregroundStyle(record.setup.colors[winner].color)
            Text("\(record.setup.teamName(winner)) win")
                .font(.title2.bold())
            Text(record.setResultsText)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                    .buttonStyle(.bordered)
                Button("Play again", systemImage: "arrow.clockwise", action: onPlayAgain)
                    .buttonStyle(.bordered)
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.black)
            }
            .controlSize(.large)
        }
        .padding(28)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 28))
        .shadow(radius: 30)
    }
}

struct CircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { CircleButtonLabel(systemImage: systemImage) }
            .accessibilityLabel(label)
    }
}

struct CircleButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color(white: 0.14), in: Circle())
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
