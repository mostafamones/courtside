//
//  padelTests.swift
//  padelTests
//
//  Created by Mostafa Mones on 01/10/2026.
//

import Foundation
import Testing
@testable import padel

/// Serve order: A1 (0), B1 (2), A2 (1), B2 (3).
private let order = [0, 2, 1, 3]

private func state(_ rules: MatchRules = .standard, _ actions: [MatchAction] = []) -> MatchState {
    MatchState.replay(rules: rules, serveOrder: order, actions: actions)
}

private func apply(_ s: MatchState, _ actions: MatchAction...) -> MatchState {
    actions.reduce(s) { current, action in
        guard let next = current.applying(action) else {
            Issue.record("Action \(action) rejected")
            return current
        }
        return next
    }
}

private func points(_ team: TeamSide, _ count: Int) -> [MatchAction] {
    Array(repeating: .point(team), count: count)
}

/// Wins a regular game for `team` and confirms it.
private func game(_ team: TeamSide) -> [MatchAction] { points(team, 4) + [.confirmGame] }

private func games(_ team: TeamSide, _ count: Int) -> [MatchAction] {
    (0..<count).flatMap { _ in game(team) }
}

struct PointScoringTests {
    @Test func pointProgression() {
        var s = state()
        #expect(s.pointLabel(for: .a) == "0")
        let labels = ["15", "30", "40"]
        for label in labels {
            s = apply(s, .point(.a))
            #expect(s.pointLabel(for: .a) == label)
        }
    }

    @Test func advantageDeuce() {
        var s = state(.standard, points(.a, 3) + points(.b, 3))
        #expect(s.pointLabel(for: .a) == "40")
        #expect(s.pointLabel(for: .b) == "40")
        s = apply(s, .point(.a))
        #expect(s.pointLabel(for: .a) == "AD")
        #expect(!s.isAwaitingConfirmation)
        s = apply(s, .point(.b))
        #expect(s.pointLabel(for: .a) == "40")
        #expect(s.pointLabel(for: .b) == "40")
        s = apply(s, .point(.b), .point(.b))
        #expect(s.pendingGameWinner == .b)
        #expect(s.pointLabel(for: .b) == "GAME")
    }

    @Test func goldenPointDecidesAtDeuce() {
        var rules = MatchRules.standard
        rules.deuceRule = .goldenPoint
        var s = state(rules, points(.a, 3) + points(.b, 3))
        #expect(s.isGoldenPoint)
        #expect(s.needsGoldenPointSide)
        s = apply(s, .chooseGoldenPointSide(.left))
        #expect(s.serveSide == .left)
        s = apply(s, .point(.b))
        #expect(s.pendingGameWinner == .b)
        // Indicator retained while awaiting confirmation.
        #expect(s.serveSide == .left)
    }

    @Test func goldenPointSideRestoredByUndoReplay() {
        var rules = MatchRules.standard
        rules.deuceRule = .goldenPoint
        let base = points(.a, 3) + points(.b, 3)
        let chosen = state(rules, base + [.chooseGoldenPointSide(.left)])
        #expect(chosen.serveSide == .left)
        let undone = state(rules, base)
        #expect(undone.goldenPointSide == nil)
        #expect(undone.serveSide == .right)
    }

    @Test func removePointOnlyAffectsCurrentGame() {
        var s = state(.standard, points(.a, 2))
        s = apply(s, .removePoint(.a))
        #expect(s.points.a == 1)
        #expect(s.pointsWon.a == 1)
        #expect(s.applying(.removePoint(.b)) == nil)
    }
}

struct ConfirmationTests {
    @Test func winningPointAwaitsConfirmation() {
        var s = state(.standard, points(.a, 4))
        #expect(s.pendingGameWinner == .a)
        #expect(s.games == .zero)
        #expect(s.applying(.point(.a)) == nil)
        #expect(s.applying(.point(.b)) == nil)
        s = apply(s, .confirmGame)
        #expect(s.games.a == 1)
        #expect(s.points == .zero)
        #expect(s.pendingGameWinner == nil)
    }

    @Test func correctionWhilePendingClearsIt() {
        var s = state(.standard, points(.a, 4))
        s = apply(s, .removePoint(.a))
        #expect(s.pendingGameWinner == nil)
        #expect(s.pointLabel(for: .a) == "40")
        #expect(s.applying(.confirmGame) == nil)
    }

    @Test func pendingRetainsServiceIndicator() {
        // Four points in the first game: last point (index 3) from the left.
        let s = state(.standard, points(.a, 4))
        #expect(s.server == 0)
        #expect(s.serveSide == .left)
    }

    @Test func confirmWithoutPendingRejected() {
        #expect(state().applying(.confirmGame) == nil)
    }
}

struct ServiceTests {
    @Test func regularGameStartsRightAndAlternates() {
        var s = state()
        #expect(s.server == 0)
        #expect(s.serveSide == .right)
        s = apply(s, .point(.a))
        #expect(s.serveSide == .left)
        s = apply(s, .point(.b))
        #expect(s.serveSide == .right)
    }

    @Test func rotationAcrossGames() {
        var s = state()
        var servers: [Int] = []
        for _ in 0..<4 {
            servers.append(s.server)
            s = apply(s, .point(.a), .point(.a), .point(.a), .point(.a), .confirmGame)
        }
        #expect(servers == [0, 2, 1, 3])
        #expect(s.server == 0)
        #expect(s.serveSide == .right)
    }

    @Test func tiebreakServiceRotation() {
        // Reach 6–6: alternate games, 12 games → rotation index back to 0.
        let actions = (0..<6).flatMap { _ in game(.a) + game(.b) }
        var s = state(.standard, actions)
        #expect(s.gameKind == .tiebreak)
        #expect(s.gameLabel == "TIEBREAK")
        var sequence: [(Int, CourtSide)] = []
        for i in 0..<7 {
            sequence.append((s.server, s.serveSide))
            s = apply(s, .point(i.isMultiple(of: 2) ? .a : .b))
        }
        #expect(sequence.map(\.0) == [0, 2, 2, 1, 1, 3, 3])
        #expect(sequence.map(\.1) == [.right, .left, .right, .left, .right, .left, .right])
    }

    @Test func nextSetAfterTiebreakStartsWithTiebreakReceiver() {
        let toTiebreak = (0..<6).flatMap { _ in game(.a) + game(.b) }
        let s = state(.standard, toTiebreak + points(.a, 7) + [.confirmGame])
        #expect(s.completedSets.count == 1)
        #expect(s.completedSets[0].games == TeamPair(a: 7, b: 6))
        #expect(s.completedSets[0].tiebreak == TeamPair(a: 7, b: 0))
        #expect(s.server == 2)
        #expect(s.gameKind == .regular)
    }
}

struct SetAndMatchTests {
    @Test func setRequiresTwoGameMargin() {
        var s = state(.standard, games(.a, 5) + games(.b, 5) + game(.a))
        #expect(s.completedSets.isEmpty)
        s = apply(s, .point(.a), .point(.a), .point(.a), .point(.a), .confirmGame)
        #expect(s.completedSets.count == 1)
        #expect(s.completedSets[0].games == TeamPair(a: 7, b: 5))
        #expect(s.games == .zero)
    }

    @Test func bestOfThreeMatch() {
        let s = state(.standard, games(.a, 6) + games(.b, 6) + games(.a, 6))
        #expect(s.winner == .a)
        #expect(s.setsWon == TeamPair(a: 2, b: 1))
        #expect(s.applying(.point(.a)) == nil)
    }

    @Test func finalGameNeedsConfirmation() {
        let s = state(.standard, games(.a, 11) + points(.a, 4))
        #expect(s.winner == nil)
        #expect(s.pendingGameWinner == .a)
        #expect(apply(s, .confirmGame).winner == .a)
    }

    @Test func fourGameSetsWithTiebreakAtFourAll() {
        var rules = MatchRules.standard
        rules.gamesPerSet = 4
        rules.setsToWin = 1
        rules.tiebreakTarget = 10
        let s = state(rules, (0..<4).flatMap { _ in game(.a) + game(.b) })
        #expect(s.gameKind == .tiebreak)
        let afterTen = apply(state(rules, (0..<4).flatMap { _ in game(.a) + game(.b) } + points(.a, 9) + points(.b, 9)), .point(.a))
        #expect(afterTen.pendingGameWinner == nil) // 10–9 not enough
        let won = apply(afterTen, .point(.a), .confirmGame)
        #expect(won.winner == .a)
        #expect(won.completedSets[0].games == TeamPair(a: 5, b: 4))
    }

    @Test func decidingMatchTiebreak() {
        var rules = MatchRules.standard
        rules.decidingSet = .matchTiebreak
        var s = state(rules, games(.a, 6) + games(.b, 6))
        #expect(s.gameKind == .matchTiebreak)
        #expect(s.gameLabel == "MATCH TIEBREAK")
        s = apply(s, .point(.b))
        #expect(s.pointLabel(for: .b) == "1")
        s = state(rules, games(.a, 6) + games(.b, 6) + points(.b, 10))
        #expect(s.pendingGameWinner == .b)
        s = apply(s, .confirmGame)
        #expect(s.winner == .b)
        #expect(s.completedSets[2].isMatchTiebreak)
        #expect(s.completedSets[2].tiebreak == TeamPair(a: 0, b: 10))
    }

    @Test func bestOfFive() {
        var rules = MatchRules.standard
        rules.setsToWin = 3
        let s = state(rules, games(.a, 12) + games(.b, 12) + games(.a, 5))
        #expect(s.winner == nil)
        #expect(state(rules, games(.a, 12) + games(.b, 12) + games(.a, 6)).winner == .a)
    }
}

@MainActor
struct StoreTests {
    private func makeStore() -> (AppStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (AppStore(directory: dir), dir)
    }

    private func setup(_ store: AppStore) -> MatchSetup {
        let players = ["Alex", "Sam", "Mo", "Jo"].map { PlayerSnapshot(store.addPlayer(name: $0)) }
        return MatchSetup(players: players)
    }

    @Test func undoAcrossGameBoundary() {
        let (store, _) = makeStore()
        store.startMatch(setup(store))
        (points(.a, 4) + [.confirmGame]).forEach { store.apply($0) }
        #expect(store.activeMatch?.state.games.a == 1)
        #expect(store.activeMatch?.state.server == 2)
        store.undo()
        let s = store.activeMatch!.state
        #expect(s.games.a == 0)
        #expect(s.pendingGameWinner == .a)
        #expect(s.server == 0)
    }

    @Test func undoReopensCompletedMatch() {
        let (store, _) = makeStore()
        var matchSetup = setup(store)
        matchSetup.rules.setsToWin = 1
        store.startMatch(matchSetup)
        games(.a, 6).forEach { store.apply($0) }
        #expect(store.activeMatch == nil)
        #expect(store.history.first?.status == .completed)
        store.undo()
        #expect(store.activeMatch?.state.pendingGameWinner == .a)
        #expect(store.history.isEmpty)
    }

    @Test func persistsAndResumes() {
        let (store, dir) = makeStore()
        store.startMatch(setup(store))
        points(.b, 2).forEach { store.apply($0) }
        let reloaded = AppStore(directory: dir)
        #expect(reloaded.activeMatch?.state.points.b == 2)
        #expect(reloaded.players.count == 4)
    }

    @Test func endEarlyAndProfileEditsDontChangeHistory() {
        let (store, _) = makeStore()
        store.startMatch(setup(store))
        store.apply(.point(.a))
        store.endActiveMatchEarly()
        #expect(store.history.first?.status == .endedEarly)
        var alex = store.players.first { $0.name == "Alex" }!
        alex.name = "Alexander"
        store.updatePlayer(alex)
        #expect(store.history.first?.setup.players[0].name == "Alex")
        #expect(store.matches(for: alex).count == 1)
    }

    @Test func startingNewMatchEndsPreviousOne() {
        let (store, _) = makeStore()
        let s = setup(store)
        store.startMatch(s)
        store.startMatch(s)
        #expect(store.matches.filter { $0.status == .inProgress }.count == 1)
        #expect(store.history.first?.status == .endedEarly)
    }
}
