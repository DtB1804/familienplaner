import Foundation
import WatchConnectivity

/// Watch-Seite: empfängt den Ausschnitt vom iPhone und merkt ihn sich für den nächsten
/// Start. "Übernehme ich" geht als Nachricht ans iPhone; gespeichert wird nur dort.
@MainActor
final class WatchStore: NSObject, ObservableObject {

    static let shared = WatchStore()

    @Published private(set) var snapshot: WatchSnapshot?
    @Published var status: String?

    private let cacheKey = "watch.snapshot"

    override init() {
        super.init()
        // Nur für die App-Store-Bildschirmfotos im Simulator (Startargument -sampleData):
        // erfundene Beispieldaten, kein WatchConnectivity.
        if ProcessInfo.processInfo.arguments.contains("-sampleData") {
            snapshot = Self.sampleSnapshot()
            return
        }
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
            if let snapshot { WidgetBridge.publish(snapshot) }
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Beispielausschnitt aus Sicht von "Tom" (gleiche erfundene Familie wie SampleData).
    static func sampleSnapshot(now: Date = Date()) -> WatchSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        // Dunkelmodus-Werte der Personenfarben aus Palette (Theme.swift)
        let leon: UInt32 = 0xFF8797, mia: UInt32 = 0xC49BFF, anna: UInt32 = 0x4FD3A0
        let events = [
            WatchSnapshot.Item(id: "s1", title: "Schule", start: at(8), end: at(13), location: "Grundschule",
                               people: "Le, Mi", rgb: leon, openRoles: [], busy: false, token: "person3"),
            WatchSnapshot.Item(id: "s2", title: "Kinderarzt", start: at(16, 30), end: at(17, 15),
                               location: "Kinderarztpraxis", people: "Mi", rgb: mia,
                               openRoles: ["Begleitet"], busy: false, token: "person4"),
            WatchSnapshot.Item(id: "s3", title: "Schwimmkurs", start: at(17), end: at(18), location: "Schwimmbad",
                               people: "Le", rgb: leon, openRoles: ["Bringt", "Holt"], busy: false, token: "person3"),
            WatchSnapshot.Item(id: "s4", title: "Elternabend", start: at(19), end: at(20, 30), location: "Grundschule",
                               people: "To, An", rgb: anna, openRoles: [], busy: false, token: "person2"),
        ]
        let open = [
            WatchSnapshot.Open(eventID: "s2", role: "accompany", roleLabel: "Begleitet", title: "Kinderarzt", start: at(16, 30)),
            WatchSnapshot.Open(eventID: "s3", role: "driveTo", roleLabel: "Bringt", title: "Schwimmkurs", start: at(17)),
            WatchSnapshot.Open(eventID: "s3", role: "driveFrom", roleLabel: "Holt", title: "Schwimmkurs", start: at(17)),
        ]
        return WatchSnapshot(generatedAt: now, viewerName: "Tom", canClaim: true, events: events, open: open)
    }

    func claim(_ open: WatchSnapshot.Open) {
        let session = WCSession.default
        guard session.isReachable else {
            status = "iPhone nicht erreichbar. Bitte in der Nähe entsperren und erneut versuchen."
            return
        }
        status = "Wird übernommen …"
        session.sendMessage([WatchSnapshot.actionKey: WatchSnapshot.claimAction,
                             WatchSnapshot.eventIDKey: open.eventID,
                             WatchSnapshot.roleKey: open.role],
                            replyHandler: { reply in
                                let text = reply[WatchSnapshot.resultKey] as? String ?? "Erledigt"
                                Task { @MainActor in WatchStore.shared.status = text }
                            },
                            errorHandler: { error in
                                Task { @MainActor in
                                    WatchStore.shared.status = "Fehlgeschlagen: \(error.localizedDescription)"
                                }
                            })
    }

    fileprivate func receive(_ context: [String: Any]) {
        guard let data = context[WatchSnapshot.contextKey] as? Data,
              let decoded = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        snapshot = decoded
        UserDefaults.standard.set(data, forKey: cacheKey)
        // Zifferblatt-Elemente lesen denselben Ausschnitt aus der App Group der Watch.
        WidgetBridge.publish(decoded)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in WatchStore.shared.receive(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in WatchStore.shared.receive(applicationContext) }
    }
}
