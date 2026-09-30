import Foundation

nonisolated enum TeamSide: Int, Codable, CaseIterable, Hashable, Sendable {
    case a = 0
    case b = 1

    var opponent: TeamSide { self == .a ? .b : .a }
}

/// Court side from the server's perspective.
nonisolated enum CourtSide: String, Codable, CaseIterable, Hashable, Sendable {
    case left
    case right
}

nonisolated enum DeuceRule: String, Codable, CaseIterable, Hashable, Sendable {
    case advantage
    case goldenPoint

    var title: String { self == .advantage ? "Advantage" : "Golden point" }
}

nonisolated enum DecidingSet: String, Codable, CaseIterable, Hashable, Sendable {
    case normal
    case matchTiebreak

    var title: String { self == .normal ? "Normal set" : "10-point match tiebreak" }
}

nonisolated struct MatchRules: Codable, Hashable, Sendable {
    /// 1 = one set, 2 = best of three, 3 = best of five.
    var setsToWin: Int
    var deuceRule: DeuceRule
    /// 4 or 6, win by two. Tiebreak is played at `gamesPerSet`–`gamesPerSet`.
    var gamesPerSet: Int
    /// 7 or 10, win by two.
    var tiebreakTarget: Int
    var decidingSet: DecidingSet

    static let matchTiebreakTarget = 10

    static let standard = MatchRules(
        setsToWin: 2,
        deuceRule: .advantage,
        gamesPerSet: 6,
        tiebreakTarget: 7,
        decidingSet: .normal
    )

    var maxSets: Int { setsToWin * 2 - 1 }
    var tiebreakTrigger: Int { gamesPerSet }

    var matchLengthTitle: String {
        switch setsToWin {
        case 1: "One set"
        case 2: "Best of three"
        default: "Best of five"
        }
    }

    var summary: String {
        var parts = [matchLengthTitle, "\(gamesPerSet)-game sets", deuceRule.title,
                     "Tiebreak to \(tiebreakTarget) at \(gamesPerSet)–\(gamesPerSet)"]
        if setsToWin > 1 && decidingSet == .matchTiebreak {
            parts.append("Deciding set: match tiebreak")
        }
        return parts.joined(separator: " · ")
    }
}
