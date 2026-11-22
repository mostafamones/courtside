import SwiftUI

/// Courtside scoreboard. Landscape lays the teams out like the court seen from the side;
/// portrait stacks them like the Watch. Tap a team's area to add a point, double tap to remove one.
struct ScoreboardView: View {
    @Environment(AppStore.self) private var store
    @Binding var setupRequest: SetupRequest?
    @Binding var isPresented: Bool
    @State private var feedback = 0
    @State private var confirmEndEarly = false
    /// Phone-only: shows team B on the left/top, e.g. when the phone is moved to the other side of the court.
    @State private var flipped = false

    /// The active match, or the match that was just completed (so the result and undo stay reachable).
    private var record: MatchRecord? {
        store.activeMatch ?? store.matches.last.flatMap { $0.status == .completed ? $0 : nil }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let record {
                let state = record.state
                court(record: record, state: state)
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
                        }
                    }
                    .alert(confirmTitle(record: record, state: state), isPresented: Binding(
                        get: { state.pendingGameWinner != nil && !state.isFinished },
                        set: { _ in }
                    )) {
                        Button("Confirm") { if store.apply(.confirmGame) { feedback += 1 } }
                        Button("Undo last point", role: .cancel) { store.undo() }
                    } message: {
                        Text(confirmMessage(state: state))
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
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .environment(\.scoreAction) { action in
            if store.apply(action) { feedback += 1 }
        }
    }

    private func court(record: MatchRecord, state: MatchState) -> some View {
        GeometryReader { geo in
            let first: TeamSide = flipped ? .b : .a
            let divider = Color(white: 0.18)
            if geo.size.width > geo.size.height {
                HStack(spacing: 0) {
                    TeamPanel(record: record, state: state, team: first, position: .left)
                    divider.frame(width: 1, height: geo.size.height / 2)
                    TeamPanel(record: record, state: state, team: first.opponent, position: .right)
                }
            } else {
                VStack(spacing: 0) {
                    TeamPanel(record: record, state: state, team: first, position: .top)
                    divider.frame(width: geo.size.width / 2, height: 1)
                    TeamPanel(record: record, state: state, team: first.opponent, position: .bottom)
                }
            }
        }
        // Keep clear of the Dynamic Island and rounded corners on the sides and top.
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(.snappy, value: flipped)
    }

    private func topBar(state: MatchState) -> some View {
        HStack {
            CircleButton(systemImage: "chevron.down", label: "Minimize") { isPresented = false }
            Spacer()
            CircleButton(systemImage: "arrow.uturn.backward", label: "Undo last action") { store.undo() }
                .disabled(record?.actions.isEmpty ?? true)
            Menu {
                Button("Switch sides", systemImage: "arrow.left.arrow.right") { flipped.toggle() }
                Button("Switch sides on Watch", systemImage: "applewatch") { store.switchWatchSides() }
                if !state.isFinished {
                    Button("End match early", systemImage: "flag.checkered", role: .destructive) {
                        confirmEndEarly = true
                    }
                }
            } label: {
                CircleButtonLabel(systemImage: "ellipsis")
            }
            .accessibilityLabel("More")
        }
        // Centred on the screen regardless of how many buttons sit on each side.
        .overlay {
            Text(state.statusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.5))
                .tracking(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func confirmTitle(record: MatchRecord, state: MatchState) -> String {
        guard let winner = state.pendingGameWinner else { return "" }
        return record.setup.teamName(winner)
    }

    private func confirmMessage(state: MatchState) -> String {
        switch state.gameKind {
        case .regular: "Win the game."
        case .tiebreak: "Win the tiebreak and the set."
        case .matchTiebreak: "Win the match tiebreak."
        }
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

/// Where a team's panel sits on screen.
enum PanelPosition {
    case left, right, top, bottom

    var isLandscape: Bool { self == .left || self == .right }
}

struct TeamPanel: View {
    @Environment(\.scoreAction) private var scoreAction
    let record: MatchRecord
    let state: MatchState
    let team: TeamSide
    let position: PanelPosition

    private enum Edge { case top, bottom }

    var body: some View {
        VStack(spacing: 0) {
            serverSlot(.top)
            Spacer(minLength: 0)
            if !position.isLandscape { scoreBlock }
            Spacer(minLength: 0)
            serverSlot(.bottom)
        }
        .padding(.top, position == .bottom ? 16 : 64)
        .padding(.bottom, position == .top ? 16 : 28)
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Landscape: score centred on the full screen height, independent of the
        // top bar / home indicator padding around the server rows.
        .overlay {
            if position.isLandscape { scoreBlock.padding(.horizontal, 44) }
        }
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

    /// Games on the outer edge, point score centred in the remaining space (so it sits
    /// toward the middle in landscape and never collides with the games), sets underneath it.
    private var scoreBlock: some View {
        let landscape = position.isLandscape
        // Sized by a hidden "00" so "GAME" shrinks to fit instead of resizing the layout.
        let font = Font.system(size: landscape ? 150 : 120, weight: .heavy, design: .rounded)
        let points = Text("00").font(font).hidden()
            .overlay {
                Text(state.pointLabel(for: team))
                    .font(font)
                    .foregroundStyle(record.setup.colors[team].color)
                    .minimumScaleFactor(0.2)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(state.pointLabel(for: team)) points")
            }
            // Previous sets hang below the score without affecting its centring,
            // so the point score and games count stay centred together.
            .overlay(alignment: .bottom) {
                SetsStrip(record: record, state: state, team: team)
                    .fixedSize()
                    .alignmentGuide(.bottom) { _ in landscape ? 16 : 14 }
            }
            .frame(maxWidth: .infinity)
        let games = Text("\(state.games[team])")
            .font(.system(size: landscape ? 64 : 52, weight: .bold, design: .rounded))
            .foregroundStyle(Color(white: 0.45))
            .accessibilityLabel("\(state.games[team]) games")
        return Group {
            switch position {
            case .left:
                HStack(spacing: 16) { games; points }
            case .right:
                HStack(spacing: 16) { points; games }
            case .top, .bottom:
                // Portrait: point score dead-centre, like the Watch.
                ZStack(alignment: .leading) {
                    points
                    games
                }
            }
        }
        .animation(.snappy, value: state.points)
    }

    private var isServing: Bool { state.servingTeam == team && !state.isFinished }

    /// Landscape mirrors the court: each team faces the net in the middle, so the server's
    /// right is the bottom of the screen on the left half and the top on the right half.
    /// Portrait keeps the server on the outer edge, like the Watch.
    private var serverEdge: Edge {
        switch position {
        case .left: state.serveSide == .right ? .bottom : .top
        case .right: state.serveSide == .right ? .top : .bottom
        case .top: .top
        case .bottom: .bottom
        }
    }

    @ViewBuilder
    private func serverSlot(_ edge: Edge) -> some View {
        Group {
            if isServing && serverEdge == edge {
                serverRow
            } else {
                Color.clear
            }
        }
        .frame(height: 36)
    }

    private var serverRow: some View {
        let name = record.setup.players[state.server].name.uppercased()
        let label = Text(name).font(.title3.weight(.semibold)).tracking(-0.5).foregroundStyle(.white)
        let alignment: Alignment = switch position {
        case .left, .right: .center
        case .top: .leading
        case .bottom: .trailing
        }
        return HStack(spacing: 8) {
            if !position.isLandscape && state.serveSide == .left {
                ServeBall(size: 14)
                label
            } else {
                label
                ServeBall(size: 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) serving from the \(state.serveSide.rawValue)")
    }
}

struct ServeBall: View {
    let size: CGFloat

    var body: some View {
        Circle().fill(Color(red: 0.45, green: 0.95, blue: 0.1)).frame(width: size, height: size)
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
