import Foundation
import Observation

/// Local, offline persistence. Each collection is a JSON file in Application Support,
/// written atomically on every change so an interrupted session can resume.
@Observable
final class AppStore {
    private(set) var players: [Player] = []
    private(set) var favourites: [Favourite] = []
    private(set) var rulePresets: [RulePreset] = []
    private(set) var matches: [MatchRecord] = []

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var sync: MatchSync?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PadelStore", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        players = load("players.json") ?? []
        // Favourites used to be called presets; pick up the old file once.
        favourites = load("favourites.json") ?? load("presets.json") ?? []
        rulePresets = load("rulePresets.json") ?? []
        matches = load("matches.json") ?? []
    }

    // MARK: Watch sync

    /// Mirrors the current match to the Watch and applies changes scored there.
    func startWatchSync() {
        let sync = MatchSync()
        sync.onReceive = { [weak self] update in self?.receiveFromWatch(update.record) }
        sync.myPlayerID = myPlayerID
        sync.favourites = sortedFavourites
        sync.activate()
        self.sync = sync
        sync.send(watchMatch)
    }

    /// The phone owner's player profile. Their team defaults to the bottom of the Watch.
    var myPlayerID: UUID? = UserDefaults.standard.string(forKey: "myPlayerID").flatMap(UUID.init(uuidString:)) {
        didSet {
            UserDefaults.standard.set(myPlayerID?.uuidString, forKey: "myPlayerID")
            sync?.myPlayerID = myPlayerID
            sync?.send(watchMatch)
        }
    }

    /// Swaps which team is on top of the Watch scoreboard, so the wearer's team can sit at the bottom.
    func switchWatchSides() { sync?.sendSwitchWatchSides() }

    /// The match the Watch should show: the active one, or the one that just finished.
    private var watchMatch: MatchRecord? {
        if let activeMatch { return activeMatch }
        guard let last = matches.last, last.status == .completed else { return nil }
        return last
    }

    private func syncFavourites() {
        sync?.favourites = sortedFavourites
        sync?.send(watchMatch)
    }

    private func receiveFromWatch(_ record: MatchRecord?) {
        guard let record else { return }
        if let index = matches.firstIndex(where: { $0.id == record.id }) {
            matches[index] = record
        } else {
            // A match started on the Watch from a favourite. Only one match is active at a time.
            for index in matches.indices where matches[index].status == .inProgress {
                end(at: index, status: .endedEarly)
            }
            matches.append(record)
        }
        save(matches, "matches.json")
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
        if myPlayerID == player.id { myPlayerID = nil }
        players.removeAll { $0.id == player.id }
        save(players, "players.json")
    }

    func player(id: UUID) -> Player? { players.first { $0.id == id } }

    func matches(for player: Player) -> [MatchRecord] {
        history.filter { $0.includes(playerID: player.id) }
    }

    // MARK: Favourites

    var sortedFavourites: [Favourite] {
        favourites.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func saveFavourite(_ favourite: Favourite) {
        var favourite = favourite
        favourite.updatedAt = Date()
        if let index = favourites.firstIndex(where: { $0.id == favourite.id }) {
            favourites[index] = favourite
        } else {
            favourites.append(favourite)
        }
        save(favourites, "favourites.json")
        syncFavourites()
    }

    func deleteFavourite(_ favourite: Favourite) {
        favourites.removeAll { $0.id == favourite.id }
        save(favourites, "favourites.json")
        syncFavourites()
    }

    // MARK: Rule presets

    var sortedRulePresets: [RulePreset] {
        rulePresets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func saveRulePreset(_ preset: RulePreset) {
        if let index = rulePresets.firstIndex(where: { $0.id == preset.id }) {
            rulePresets[index] = preset
        } else {
            rulePresets.append(preset)
        }
        save(rulePresets, "rulePresets.json")
    }

    func deleteRulePreset(_ preset: RulePreset) {
        rulePresets.removeAll { $0.id == preset.id }
        save(rulePresets, "rulePresets.json")
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

    private func persistMatches() {
        save(matches, "matches.json")
        sync?.send(watchMatch)
    }

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
