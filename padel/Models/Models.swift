import Foundation
import SwiftUI

/// Local player profile. Kept separate from any future account identity:
/// `linkedAccountID` can be set later without touching historical records.
nonisolated struct Player: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var nickname: String?
    var linkedAccountID: String?
    var createdAt = Date()

    var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty { return nickname }
        return name
    }
}

/// Frozen copy of a player at the time a match or preset was created,
/// so editing a profile never rewrites history.
nonisolated struct PlayerSnapshot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String

    init(_ player: Player) {
        id = player.id
        name = player.displayName
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

nonisolated enum TeamColor: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case gold, turquoise, coral, violet, lime, sky, pink, white

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .gold: Color(red: 1.0, green: 0.73, blue: 0.0)
        case .turquoise: Color(red: 0.0, green: 0.86, blue: 0.75)
        case .coral: Color(red: 1.0, green: 0.42, blue: 0.36)
        case .violet: Color(red: 0.66, green: 0.5, blue: 1.0)
        case .lime: Color(red: 0.62, green: 0.93, blue: 0.2)
        case .sky: Color(red: 0.3, green: 0.68, blue: 1.0)
        case .pink: Color(red: 1.0, green: 0.45, blue: 0.75)
        case .white: Color(white: 0.95)
        }
    }
}

/// Everything needed to start a match: lineup, colors, rules and service order.
nonisolated struct MatchSetup: Codable, Hashable, Sendable {
    /// Indices 0–1 are team A (shown top on Watch / left on iPhone), 2–3 team B.
    var players: [PlayerSnapshot]
    var colors: TeamPair<TeamColor> = TeamPair(a: .gold, b: .turquoise)
    var rules: MatchRules = .standard
    /// Player index of the first server.
    var firstServer: Int = 0
    /// Player index of the opposing team's first server.
    var opposingFirstServer: Int = 2

    static func partner(of index: Int) -> Int { index ^ 1 }
    static func team(of index: Int) -> TeamSide { index < 2 ? .a : .b }

    var serveOrder: [Int] {
        [firstServer, opposingFirstServer, Self.partner(of: firstServer), Self.partner(of: opposingFirstServer)]
    }

    func players(of team: TeamSide) -> [PlayerSnapshot] {
        team == .a ? Array(players[0...1]) : Array(players[2...3])
    }

    func teamName(_ team: TeamSide) -> String {
        players(of: team).map(\.name).joined(separator: " & ")
    }

    var isValid: Bool {
        players.count == 4
            && Set(players.map(\.id)).count == 4
            && Self.team(of: firstServer) != Self.team(of: opposingFirstServer)
            && colors.a != colors.b
    }
}

nonisolated struct MatchPreset: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var setup: MatchSetup
    var updatedAt = Date()
}

nonisolated enum MatchStatus: String, Codable, Hashable, Sendable {
    case inProgress
    case completed
    case endedEarly
}

/// Which device is allowed to score. Only the phone exists for now; kept on the
/// record so the Watch handover protocol can build on it.
nonisolated enum ScoringController: String, Codable, Hashable, Sendable {
    case phone
    case watch
}

nonisolated struct MatchRecord: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var setup: MatchSetup
    var presetName: String?
    var actions: [LoggedAction] = []
    var status: MatchStatus = .inProgress
    var controller: ScoringController = .phone
    var startedAt = Date()
    var endedAt: Date?

    var state: MatchState {
        MatchState.replay(rules: setup.rules, serveOrder: setup.serveOrder, actions: actions.map(\.action))
    }

    var duration: TimeInterval {
        let end = endedAt ?? actions.last?.timestamp ?? startedAt
        return max(end.timeIntervalSince(startedAt), 0)
    }

    func includes(playerID: UUID) -> Bool {
        setup.players.contains { $0.id == playerID }
    }
}
