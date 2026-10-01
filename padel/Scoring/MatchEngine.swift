import Foundation

nonisolated struct TeamPair<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var a: Value
    var b: Value

    subscript(team: TeamSide) -> Value {
        get { team == .a ? a : b }
        set { if team == .a { a = newValue } else { b = newValue } }
    }
}

nonisolated extension TeamPair where Value == Int {
    static var zero: TeamPair<Int> { TeamPair(a: 0, b: 0) }
}

nonisolated enum MatchAction: Codable, Hashable, Sendable {
    case point(TeamSide)
    case removePoint(TeamSide)
    case confirmGame
    /// Golden point: the receiving team picks which side the server serves to.
    case chooseGoldenPointSide(CourtSide)
}

nonisolated struct LoggedAction: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var action: MatchAction
    var timestamp = Date()
}

nonisolated enum GameKind: Codable, Hashable, Sendable {
    case regular
    case tiebreak
    case matchTiebreak
}

nonisolated struct SetResult: Codable, Hashable, Sendable {
    var games: TeamPair<Int>
    /// Points of the tiebreak that decided the set, if any.
    var tiebreak: TeamPair<Int>?
    var isMatchTiebreak: Bool = false

    var winner: TeamSide {
        if let tiebreak, isMatchTiebreak { return tiebreak.a > tiebreak.b ? .a : .b }
        return games.a > games.b ? .a : .b
    }
}

/// Pure, deterministic match state. Every change goes through `applying(_:)`,
/// so the full state can be rebuilt from an action log (used for undo and persistence).
nonisolated struct MatchState: Codable, Hashable, Sendable {
    let rules: MatchRules
    /// Player indices (0–1 team A, 2–3 team B) in service rotation order.
    let serveOrder: [Int]

    private(set) var completedSets: [SetResult] = []
    private(set) var games: TeamPair<Int> = .zero
    private(set) var points: TeamPair<Int> = .zero
    private(set) var gameKind: GameKind = .regular
    /// Index into `serveOrder` of the player serving the first point of the current game.
    private(set) var rotationIndex = 0
    private(set) var pendingGameWinner: TeamSide?
    private(set) var goldenPointSide: CourtSide?
    private(set) var winner: TeamSide?
    private(set) var pointsWon: TeamPair<Int> = .zero

    init(rules: MatchRules, serveOrder: [Int]) {
        precondition(serveOrder.count == 4, "Serve order needs four players")
        self.rules = rules
        self.serveOrder = serveOrder
    }

    static func replay(rules: MatchRules, serveOrder: [Int], actions: [MatchAction]) -> MatchState {
        actions.reduce(MatchState(rules: rules, serveOrder: serveOrder)) { $0.applying($1) ?? $0 }
    }

    // MARK: Derived

    var setsWon: TeamPair<Int> {
        completedSets.reduce(into: .zero) { $0[$1.winner] += 1 }
    }

    var isFinished: Bool { winner != nil }
    var isAwaitingConfirmation: Bool { pendingGameWinner != nil }

    var isGoldenPoint: Bool {
        gameKind == .regular && rules.deuceRule == .goldenPoint && points.a == 3 && points.b == 3
    }

    /// Needs the receiving team's side choice before the golden point is played.
    var needsGoldenPointSide: Bool {
        isGoldenPoint && goldenPointSide == nil && pendingGameWinner == nil && winner == nil
    }

    /// Point index used for the service indicator. While a game is awaiting
    /// confirmation it stays on the point that was just played.
    private var servicePointIndex: Int {
        let total = points.a + points.b
        return pendingGameWinner != nil ? max(total - 1, 0) : total
    }

    /// Player index (into setup players) currently serving.
    var server: Int {
        let n = servicePointIndex
        let offset: Int
        switch gameKind {
        case .regular: offset = 0
        // Tiebreak: first point by one server, then two points each in rotation.
        case .tiebreak, .matchTiebreak: offset = (n + 1) / 2
        }
        return serveOrder[(rotationIndex + offset) % 4]
    }

    var servingTeam: TeamSide { server < 2 ? .a : .b }

    var serveSide: CourtSide {
        if let goldenPointSide, gameKind == .regular { return goldenPointSide }
        return servicePointIndex % 2 == 0 ? .right : .left
    }

    /// 1-based game number within the current set.
    var gameNumber: Int { games.a + games.b + 1 }

    var setNumber: Int { completedSets.count + 1 }

    var gameLabel: String {
        switch gameKind {
        case .regular: "GAME \(gameNumber)"
        case .tiebreak: "TIEBREAK"
        case .matchTiebreak: "MATCH TIEBREAK"
        }
    }

    /// e.g. "SET 1 · GAME 3", shown above the scoreboard.
    var statusLabel: String {
        switch gameKind {
        case .regular: "SET \(setNumber) · GAME \(gameNumber)"
        case .tiebreak: "SET \(setNumber) · TIEBREAK"
        case .matchTiebreak: "MATCH TIEBREAK"
        }
    }

    func pointLabel(for team: TeamSide) -> String {
        if pendingGameWinner == team { return "GAME" }
        let mine = points[team], theirs = points[team.opponent]
        guard gameKind == .regular else { return "\(mine)" }
        if mine >= 3 && theirs >= 3 {
            if mine == theirs { return "40" }
            return mine > theirs ? "AD" : "40"
        }
        return ["0", "15", "30", "40"][min(mine, 3)]
    }

    // MARK: Transitions

    /// Returns the new state, or `nil` if the action isn't allowed right now.
    func applying(_ action: MatchAction) -> MatchState? {
        var next = self
        switch action {
        case .point(let team):
            guard winner == nil, pendingGameWinner == nil else { return nil }
            next.points[team] += 1
            next.pointsWon[team] += 1
            next.pendingGameWinner = next.computeGameWinner()

        case .removePoint(let team):
            guard winner == nil, points[team] > 0 else { return nil }
            next.points[team] -= 1
            next.pointsWon[team] -= 1
            next.pendingGameWinner = next.computeGameWinner()
            if next.pendingGameWinner == nil && !next.isGoldenPoint {
                next.goldenPointSide = nil
            }

        case .confirmGame:
            guard winner == nil, let gameWinner = pendingGameWinner else { return nil }
            next.confirm(gameWinner)

        case .chooseGoldenPointSide(let side):
            guard isGoldenPoint, pendingGameWinner == nil, winner == nil else { return nil }
            next.goldenPointSide = side
        }
        return next
    }

    private func computeGameWinner() -> TeamSide? {
        for team in TeamSide.allCases {
            let mine = points[team], theirs = points[team.opponent]
            switch gameKind {
            case .regular:
                if rules.deuceRule == .goldenPoint {
                    if mine >= 4 && mine > theirs { return team }
                } else if mine >= 4 && mine - theirs >= 2 {
                    return team
                }
            case .tiebreak:
                if mine >= rules.tiebreakTarget && mine - theirs >= 2 { return team }
            case .matchTiebreak:
                if mine >= MatchRules.matchTiebreakTarget && mine - theirs >= 2 { return team }
            }
        }
        return nil
    }

    private mutating func confirm(_ gameWinner: TeamSide) {
        let loser = gameWinner.opponent
        var setFinished: SetResult?

        switch gameKind {
        case .regular:
            games[gameWinner] += 1
            if games[gameWinner] >= rules.gamesPerSet && games[gameWinner] - games[loser] >= 2 {
                setFinished = SetResult(games: games)
            }
        case .tiebreak:
            games[gameWinner] += 1
            setFinished = SetResult(games: games, tiebreak: points)
        case .matchTiebreak:
            games[gameWinner] += 1
            setFinished = SetResult(games: games, tiebreak: points, isMatchTiebreak: true)
        }

        rotationIndex = (rotationIndex + 1) % 4
        points = .zero
        pendingGameWinner = nil
        goldenPointSide = nil

        if let setFinished {
            completedSets.append(setFinished)
            games = .zero
            let won = setsWon
            if won[gameWinner] >= rules.setsToWin {
                winner = gameWinner
                gameKind = .regular
                return
            }
            let isDeciding = rules.setsToWin > 1
                && won.a == rules.setsToWin - 1 && won.b == rules.setsToWin - 1
            gameKind = isDeciding && rules.decidingSet == .matchTiebreak ? .matchTiebreak : .regular
        } else if games.a == rules.tiebreakTrigger && games.b == rules.tiebreakTrigger {
            gameKind = .tiebreak
        } else {
            gameKind = .regular
        }
    }
}
