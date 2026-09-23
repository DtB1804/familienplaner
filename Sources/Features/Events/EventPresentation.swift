import CoreData
import Foundation

/// Was ein bestimmtes Familienmitglied von einem Termin sieht.
///
/// Zwei Stufen:
/// 1. Projektion beim Speichern (EventService): "nur Belegt" ist schon in den Daten
///    reduziert. Das ist echter Schutz.
/// 2. Anzeige-Schalter für Kinder (CLAUDE.md, bewusste Ausnahme zu Regel 2): Stellen
///    die Eltern den Haushalt auf "Kinder sehen nur Belegt", zeigt die App Kindern
///    Termine der Erwachsenen ohne Titel und Ort. Die Daten liegen trotzdem vor.
enum EventPresentation {

    static let busyTitle = "Belegt"

    static func title(of event: CDEvent, for viewer: CDMember?, in household: CDHousehold?) -> String {
        hidesDetails(event, for: viewer, in: household) ? busyTitle : (event.title ?? "Ohne Titel")
    }

    static func location(of event: CDEvent, for viewer: CDMember?, in household: CDHousehold?) -> String? {
        hidesDetails(event, for: viewer, in: household) ? nil : event.locationName
    }

    /// Wird der Termin als reine Belegtzeit gezeigt?
    static func isBusyOnly(_ event: CDEvent, for viewer: CDMember?, in household: CDHousehold?) -> Bool {
        EventVisibility(rawValue: event.visibilityRaw ?? "") == .busyOnly
            || hidesDetails(event, for: viewer, in: household)
    }

    private static func hidesDetails(_ event: CDEvent, for viewer: CDMember?, in household: CDHousehold?) -> Bool {
        guard let viewer, viewer.role == .child,
              let household, !household.childrenSeeAdultTitles else { return false }
        // Termine, die ein Kind betreffen, bleiben für Kinder immer lesbar.
        let subjects = EventService.subjects(of: event)
        return !subjects.contains { $0.role == .child }
    }
}

extension EventKind {
    var label: String {
        switch self {
        case .appointment: return "Termin"
        case .statusBlock: return "Dienst"
        }
    }
}
