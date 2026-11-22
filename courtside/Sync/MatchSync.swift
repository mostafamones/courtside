import Foundation
import WatchConnectivity

/// Keeps the current match in sync between the iPhone and the Watch.
/// Each side sends the whole record after every change; the newest change wins.
/// `nil` means there is no match to show.
final class MatchSync: NSObject, WCSessionDelegate {
    nonisolated struct Update: Sendable {
        var record: MatchRecord?
        /// Sent by the phone only.
        var myPlayerID: UUID?
        /// Sent by the phone only; `nil` when the update came from the Watch.
        var favourites: [Favourite]?
    }

    /// Called on the main actor with a record changed on the other device.
    var onReceive: ((Update) -> Void)?
    /// Phone only: the owner's player profile, sent with every match so the Watch can put their team at the bottom.
    var myPlayerID: UUID?
    /// Phone only: favourites the Watch can start a match from.
    var favourites: [Favourite]?
    /// Watch only: called with the phone's favourites whenever they arrive.
    var onFavourites: (([Favourite]) -> Void)?
    /// Watch only: called when the phone asks to swap which team is on top.
    var onSwitchWatchSides: (() -> Void)?

    private var lastChange = Date.distantPast
    private var pending: [String: Any]?
    private var pendingSwitches = 0

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ record: MatchRecord?) {
        lastChange = Date()
        var payload: [String: Any] = ["sentAt": lastChange]
        if let record, let data = try? JSONEncoder().encode(record) { payload["record"] = data }
        if let myPlayerID { payload["myPlayerID"] = myPlayerID.uuidString }
        if let favourites, let data = try? JSONEncoder().encode(favourites) { payload["favourites"] = data }
        pending = payload
        flush()
    }

    func sendSwitchWatchSides() {
        pendingSwitches += 1
        flush()
    }

    /// Latest state for when the other side next wakes up, plus an immediate message if it's reachable.
    private func flush() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #else
        guard session.isCompanionAppInstalled else { return }
        #endif
        // Sent as toggles so it stays in step with "Switch sides" on the Watch itself.
        for _ in 0..<pendingSwitches {
            let message: [String: Any] = ["switchWatchSides": true]
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil) { _ in session.transferUserInfo(message) }
            } else {
                session.transferUserInfo(message)
            }
        }
        pendingSwitches = 0
        guard let payload = pending else { return }
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            // If the live message fails, queue it so it's delivered once the other side wakes up.
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        }
    }

    private func receive(sentAt: Date, update: Update) {
        // Favourites aren't part of the match, so they apply even if the match change is stale.
        if let favourites = update.favourites { onFavourites?(favourites) }
        guard sentAt > lastChange else { return }
        lastChange = sentAt
        onReceive?(update)
    }

    // MARK: WCSessionDelegate

    nonisolated private func handle(_ payload: [String: Any]) {
        if payload["switchWatchSides"] != nil {
            Task { @MainActor in self.onSwitchWatchSides?() }
            return
        }
        guard let sentAt = payload["sentAt"] as? Date else { return }
        let record = (payload["record"] as? Data).flatMap { try? JSONDecoder().decode(MatchRecord.self, from: $0) }
        let myPlayerID = (payload["myPlayerID"] as? String).flatMap(UUID.init(uuidString:))
        let favourites = (payload["favourites"] as? Data).flatMap { try? JSONDecoder().decode([Favourite].self, from: $0) }
        let update = Update(record: record, myPlayerID: myPlayerID, favourites: favourites)
        Task { @MainActor in self.receive(sentAt: sentAt, update: update) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        if !context.isEmpty { handle(context) }
        Task { @MainActor in self.flush() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        handle(context)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #else
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }
    #endif

    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }
    #endif
}
