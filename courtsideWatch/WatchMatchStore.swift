import Foundation
import Observation

/// Mirror of the iPhone's current match. Matches start on the phone, or here from one of the
/// phone's favourites; every change is sent back. Cached so it survives relaunches.
@Observable
final class WatchMatchStore {
    /// `nil` until a match is started.
    private(set) var record: MatchRecord?
    /// Synced from the phone.
    private(set) var favourites: [Favourite] = []

    /// Puts team B on top (switched here or from the phone), so the wearer can keep their own team at the bottom.
    var flipped: Bool {
        didSet { defaults.set(flipped, forKey: Self.flippedKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let closedKey = "watchClosedMatchID"
    @ObservationIgnored private let sync = MatchSync()
    private static let key = "watchActiveMatch"
    private static let flippedKey = "watchFlipped"
    private static let myPlayerKey = "watchMyPlayerID"
    private static let favouritesKey = "watchFavourites"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        flipped = defaults.bool(forKey: Self.flippedKey)
        if let data = defaults.data(forKey: Self.key) {
            record = try? JSONDecoder().decode(MatchRecord.self, from: data)
        }
        if let data = defaults.data(forKey: Self.favouritesKey),
           let saved = try? JSONDecoder().decode([Favourite].self, from: data) {
            favourites = saved
        }
        sync.onReceive = { [weak self] update in self?.receive(update.record, myPlayerID: update.myPlayerID) }
        sync.onFavourites = { [weak self] favourites in
            self?.favourites = favourites
            if let data = try? JSONEncoder().encode(favourites) { self?.defaults.set(data, forKey: Self.favouritesKey) }
        }
        sync.onSwitchWatchSides = { [weak self] in self?.flipped.toggle() }
        sync.activate()
    }

    private func receive(_ incoming: MatchRecord?, myPlayerID: UUID?) {
        if let myPlayerID { defaults.set(myPlayerID.uuidString, forKey: Self.myPlayerKey) }
        // Don't reopen a finished match the user already left.
        if let incoming, incoming.state.isFinished,
           incoming.id.uuidString == defaults.string(forKey: Self.closedKey) {
            record = nil
            save()
            return
        }
        let isNewMatch = incoming != nil && incoming?.id != record?.id
        record = incoming
        save()
        if isNewMatch, let incoming { putOwnerAtBottom(incoming) }
    }

    /// Starts a match from a favourite and hands it to the phone.
    func start(_ favourite: Favourite) {
        let record = MatchRecord(setup: favourite.setup, presetName: favourite.name)
        putOwnerAtBottom(record)
        commit(record)
    }

    /// A new match starts with the owner's team at the bottom; "Switch sides" still overrides it.
    private func putOwnerAtBottom(_ record: MatchRecord) {
        guard let me = defaults.string(forKey: Self.myPlayerKey).flatMap(UUID.init(uuidString:)),
              let index = record.setup.players.firstIndex(where: { $0.id == me }) else { return }
        flipped = MatchSetup.team(of: index) == .a
    }

    var canUndo: Bool { !(record?.actions.isEmpty ?? true) }

    @discardableResult
    func apply(_ action: MatchAction) -> Bool {
        guard var record, record.state.applying(action) != nil else { return false }
        record.actions.append(LoggedAction(action: action))
        if record.state.isFinished {
            record.status = .completed
            record.endedAt = Date()
        }
        commit(record)
        return true
    }

    func undo() {
        guard var record, canUndo else { return }
        record.actions.removeLast()
        record.status = .inProgress
        record.endedAt = nil
        commit(record)
    }

    /// Leaves a finished match and returns to the home screen. The match stays saved on the phone.
    func close() {
        guard record?.state.isFinished == true else { return }
        defaults.set(record?.id.uuidString, forKey: Self.closedKey)
        record = nil
        save()
    }

    private func commit(_ record: MatchRecord) {
        self.record = record
        save()
        sync.send(record)
    }

    private func save() {
        if let record, let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
