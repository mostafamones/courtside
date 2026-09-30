import Foundation
import Observation

/// Local, offline persistence. Each collection is a JSON file in Application Support,
/// written atomically on every change so an interrupted session can resume.
@Observable
final class AppStore {
    private(set) var players: [Player] = []
    private(set) var presets: [MatchPreset] = []
    private(set) var matches: [MatchRecord] = []

    @ObservationIgnored private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PadelStore", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        players = load("players.json") ?? []
        presets = load("presets.json") ?? []
        matches = load("matches.json") ?? []
    }

    // MARK: Players

    var sortedPlayers: [Player] {
        players.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    @discardableResult
    func addPlayer(name: String, nickname: String? = nil) -> Player {
        let player = Player(name: name.trimmingCharacters(in: .whitespaces), nickname: nickname?.nilIfBlank)
        players.append(player)
        save(players, "players.json")
        return player
    }

    func updatePlayer(_ player: Player) {
        guard let index = players.firstIndex(where: { $0.id == player.id }) else { return }
        players[index] = player
        save(players, "players.json")
    }

    func deletePlayer(_ player: Player) {
        players.removeAll { $0.id == player.id }
        save(players, "players.json")
    }

    func player(id: UUID) -> Player? { players.first { $0.id == id } }

    func matches(for player: Player) -> [MatchRecord] {
        history.filter { $0.includes(playerID: player.id) }
    }

    // MARK: Presets

    func savePreset(_ preset: MatchPreset) {
        var preset = preset
        preset.updatedAt = Date()
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        save(presets, "presets.json")
    }

    func deletePreset(_ preset: MatchPreset) {
        presets.removeAll { $0.id == preset.id }
        save(presets, "presets.json")
    }

    // MARK: Matches

    var activeMatch: MatchRecord? { matches.last { $0.status == .inProgress } }

    var history: [MatchRecord] {
        matches.filter { $0.status != .inProgress }.sorted { $0.startedAt > $1.startedAt }
    }

    @discardableResult
    func startMatch(_ setup: MatchSetup, presetName: String? = nil) -> MatchRecord {
        // Only one active match at a time; an abandoned one is kept as ended early.
        for index in matches.indices where matches[index].status == .inProgress {
            end(at: index, status: .endedEarly)
        }
        let record = MatchRecord(setup: setup, presetName: presetName)
        matches.append(record)
        persistMatches()
        return record
    }

    /// Applies a scoring action to the active match. Returns false if it isn't allowed.
    @discardableResult
    func apply(_ action: MatchAction) -> Bool {
        guard let index = activeIndex else { return false }
        guard let next = matches[index].state.applying(action) else { return false }
        matches[index].actions.append(LoggedAction(action: action))
        if next.isFinished {
            end(at: index, status: .completed)
        }
        persistMatches()
        return true
    }

    /// Undoes the last action of the most recent match, including reopening a
    /// match that was just completed by confirming its final game.
    func undo() {
        guard let index = undoableIndex, !matches[index].actions.isEmpty else { return }
        matches[index].actions.removeLast()
        if matches[index].status == .completed {
            matches[index].status = .inProgress
            matches[index].endedAt = nil
        }
        persistMatches()
    }

    func endActiveMatchEarly() {
        guard let index = activeIndex else { return }
        end(at: index, status: .endedEarly)
        persistMatches()
    }

    func deleteMatch(_ record: MatchRecord) {
        matches.removeAll { $0.id == record.id }
        persistMatches()
    }

    func match(id: UUID) -> MatchRecord? { matches.first { $0.id == id } }

    private var activeIndex: Int? { matches.lastIndex { $0.status == .inProgress } }

    private var undoableIndex: Int? {
        if let activeIndex { return activeIndex }
        // Allow undoing the confirmation that just finished the latest match.
        guard let last = matches.indices.last, matches[last].status == .completed else { return nil }
        return last
    }

    private func end(at index: Int, status: MatchStatus) {
        matches[index].status = status
        matches[index].endedAt = matches[index].actions.last?.timestamp ?? Date()
        if status == .endedEarly { matches[index].endedAt = Date() }
    }

    private func persistMatches() { save(matches, "matches.json") }

    // MARK: Files

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            assertionFailure("Failed to save \(name): \(error)")
        }
    }
}

nonisolated extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
