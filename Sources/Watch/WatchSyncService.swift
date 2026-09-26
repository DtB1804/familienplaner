import CoreData
import WatchConnectivity
import os

/// iPhone-Seite der Apple-Watch-Anbindung.
///
/// Schickt der Watch nach jeder Änderung einen fertigen Ausschnitt der nächsten drei Tage
/// (`updateApplicationContext`, iOS liefert ihn aus, sobald die Watch erreichbar ist) und
/// nimmt von der Watch "Übernehme ich" entgegen. Gespeichert wird nur auf dem iPhone.
@MainActor
final class WatchSyncService: NSObject {

    static let shared = WatchSyncService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                category: "Watch")
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private let horizonDays = 3

    func start() {
        guard WCSession.isSupported(), observers.isEmpty else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        for name in [Notification.Name.NSManagedObjectContextDidSave, .NSPersistentStoreRemoteChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.schedulePush() }
            })
        }
    }

    /// Gebündelt: viele Speichervorgänge hintereinander lösen eine Übertragung aus.
    func schedulePush() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            push()
        }
    }

    func push() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let snapshot = makeSnapshot(),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try session.updateApplicationContext([WatchSnapshot.contextKey: data])
        } catch {
            logger.error("Übertragung an die Watch fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Ausschnitt bauen

    private func makeSnapshot() -> WatchSnapshot? {
        let context = PersistenceController.shared.viewContext
        guard let household = try? HouseholdService.fetchHousehold(in: context),
              let me = CurrentMember.resolve(in: context, household: household) else { return nil }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: horizonDays, to: start) ?? start
        let events = (try? context.fetch(EventService.eventsRequest(from: start, to: end))) ?? []

        let items: [WatchSnapshot.Item] = events.compactMap { event in
            guard let id = event.id, let from = event.startAt, let to = event.endAt else { return nil }
            let subjects = EventService.subjects(of: event)
            let busy = EventPresentation.isBusyOnly(event, for: me, in: household)
            let required = RequiredRoles.decode(event.requiredRolesRaw)
            let covered = EventService.coveredRoles(of: event)
            return WatchSnapshot.Item(
                id: id.uuidString,
                title: EventPresentation.title(of: event, for: me, in: household),
                start: from, end: to,
                location: EventPresentation.location(of: event, for: me, in: household),
                people: subjects.compactMap(\.shortName).joined(separator: ", "),
                rgb: busy ? Palette.darkRGB("busy") : Palette.darkRGB(subjects.first?.colorToken ?? "person1"),
                openRoles: required.filter { !covered.contains($0) }.map(\.label),
                busy: busy)
        }

        let open = me.role == .adult
            ? ((try? EventService.openResponsibilities(within: horizonDays, in: context)) ?? []).map {
                WatchSnapshot.Open(eventID: $0.eventID.uuidString, role: $0.role.rawValue,
                                   roleLabel: $0.role.label, title: $0.eventTitle, start: $0.startAt)
            }
            : []

        return WatchSnapshot(generatedAt: Date(), viewerName: me.displayName ?? "",
                             canClaim: me.role == .adult, events: items, open: open)
    }

    // MARK: - "Übernehme ich" von der Watch

    fileprivate func handleClaim(eventID: String, role: String) -> String {
        guard let uuid = UUID(uuidString: eventID),
              let participationRole = ParticipationRole(rawValue: role) else { return "Nicht möglich" }
        let outcome = ClaimActions.claim(eventID: uuid, role: participationRole, scope: .single)
        push()
        return outcome.message
    }
}

extension WatchSyncService: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in WatchSyncService.shared.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Nach einem Wechsel der Watch neu aktivieren (Apple-Vorgabe für iOS).
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in WatchSyncService.shared.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchSnapshot.actionKey] as? String == WatchSnapshot.claimAction,
              let eventID = message[WatchSnapshot.eventIDKey] as? String,
              let role = message[WatchSnapshot.roleKey] as? String else {
            replyHandler([WatchSnapshot.resultKey: "Unbekannte Aktion"])
            return
        }
        Task { @MainActor in
            let result = WatchSyncService.shared.handleClaim(eventID: eventID, role: role)
            replyHandler([WatchSnapshot.resultKey: result])
        }
    }
}
