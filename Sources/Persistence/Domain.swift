import Foundation

// MARK: - Aufzählungen
//
// Alle Enums werden als String in Core Data abgelegt (Felder mit Suffix "Raw").
// Grund: CloudKit-Schemata lassen sich nicht rückwirkend umnummerieren, ein
// Integer-Enum wäre bei jeder Erweiterung ein Migrationsrisiko.

public enum MemberRole: String, CaseIterable, Codable {
    case adult
    case child
    case guest
}

/// Unterscheidet, ob ein Mitglied ein eigenständiger CloudKit-Teilnehmer ist
/// oder ein reines Profil, das von einem Erwachsenen gepflegt wird.
/// Siehe offener Punkt 1 im Datenmodell-Dokument.
public enum MemberAccountKind: String, CaseIterable, Codable {
    case participant
    case managed
}

public enum EventKind: String, CaseIterable, Codable {
    case appointment
    case statusBlock
}

public enum EventOrigin: String, CaseIterable, Codable {
    case manual
    case imported
    case fromSuggestion
}

public enum EventVisibility: String, CaseIterable, Codable {
    case household
    case busyOnly
}

/// Rollen innerhalb eines Termins. `subject` ist die betroffene Person,
/// `driveTo`/`driveFrom` sind die Zuständigkeiten, um die es im Familienalltag geht.
public enum ParticipationRole: String, CaseIterable, Codable, Identifiable {
    case subject
    case driveTo
    case driveFrom
    case accompany
    case informed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .subject: return "Betrifft"
        case .driveTo: return "Bringt"
        case .driveFrom: return "Holt"
        case .accompany: return "Begleitet"
        case .informed: return "Informiert"
        }
    }

    /// Rollen, die eine Zuständigkeit bedeuten und offen bleiben können.
    public static var responsibilityRoles: [ParticipationRole] { [.driveTo, .driveFrom, .accompany] }
}

public enum ParticipationStatus: String, CaseIterable, Codable {
    case claimed
    case confirmed
    case declined
}

public enum CalendarSourceKind: String, CaseIterable, Codable {
    case ekLocal
    case ekSubscribed
    case appInternal
}

public enum CalendarVisibility: String, CaseIterable, Codable {
    case hidden
    case busyOnly
    case full

    public var label: String {
        switch self {
        case .hidden: return "Nicht übernehmen"
        case .busyOnly: return "Nur als Belegtzeit"
        case .full: return "Mit Titel und Details"
        }
    }
}

public enum CalendarSyncDirection: String, CaseIterable, Codable {
    case readOnly
    case twoWay

    public var label: String {
        switch self {
        case .readOnly: return "Nur lesen"
        case .twoWay: return "Auch zurückschreiben"
        }
    }
}

public enum MirrorDirection: String, Codable { case `import`, export }
/// `joined`: Der Termin wurde schon von einem anderen Familienmitglied aus einem
/// gemeinsamen Kalender übernommen; dieses Gerät hängt sich nur als Betroffener an.
public enum MirrorState: String, Codable { case pending, synced, failed, joined }

public enum SuggestionSourceKind: String, CaseIterable, Codable {
    case screenshot, photo, pdf, sharedText, dictation
}

public enum SuggestionStatus: String, CaseIterable, Codable {
    case pending, accepted, rejected
}

// MARK: - Offene Zuständigkeit

/// Eine Zuständigkeit, die ein Termin verlangt, für die es aber noch keine
/// Beteiligung gibt. Bewusst ein reiner Wert, keine gespeicherte Entität:
/// siehe ARCHITEKTUR.md, Abschnitt "Abweichung vom Datenmodell v1".
public struct OpenResponsibility: Identifiable, Hashable {
    public let eventID: UUID
    public let role: ParticipationRole
    public let startAt: Date
    public let eventTitle: String

    public var id: String { "\(eventID.uuidString)-\(role.rawValue)" }
}

// MARK: - Kodierung der geforderten Rollen

public enum RequiredRoles {
    /// Speicherform: kommagetrennte Rohwerte, z. B. "driveTo,driveFrom".
    /// Ein String statt einer Transformable-Eigenschaft, weil Transformables
    /// mit CloudKit einen eigenen Value Transformer erfordern und bei
    /// Schema-Änderungen brechen.
    public static func encode(_ roles: [ParticipationRole]) -> String {
        roles.map(\.rawValue).joined(separator: ",")
    }

    public static func decode(_ raw: String?) -> [ParticipationRole] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { ParticipationRole(rawValue: String($0)) }
    }
}
