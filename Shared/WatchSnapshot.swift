import Foundation

/// Was das iPhone der Apple Watch schickt: ein fertig aufbereiteter Ausschnitt der
/// nächsten Tage. Titel und Orte sind bereits für das jeweilige Mitglied reduziert
/// ("Belegt", Kinderansicht). Die Watch hat keinen eigenen Datenbestand.
/// Gemeinsam genutzt von iOS-App und Watch-App.
struct WatchSnapshot: Codable, Equatable {
    var generatedAt: Date
    var viewerName: String
    var canClaim: Bool
    var events: [Item]
    var open: [Open]

    struct Item: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var location: String?
        /// Kürzel der betroffenen Personen, z. B. "DB, JO"
        var people: String
        /// Personenfarbe (Dunkelmodus-Wert, die Watch ist immer dunkel)
        var rgb: UInt32
        /// Offene Zuständigkeiten, z. B. ["Holt"]
        var openRoles: [String]
        var busy: Bool
    }

    struct Open: Codable, Identifiable, Hashable {
        var eventID: String
        var role: String
        var roleLabel: String
        var title: String
        var start: Date
        var id: String { "\(eventID)-\(role)" }
    }

    static let contextKey = "snapshot"
    static let actionKey = "action"
    static let claimAction = "claim"
    static let eventIDKey = "eventID"
    static let roleKey = "role"
    static let resultKey = "result"
}
