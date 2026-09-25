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
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
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
