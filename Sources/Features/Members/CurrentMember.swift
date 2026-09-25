import CoreData
import Foundation

/// Wer benutzt dieses Gerät?
///
/// Bewusst gerätelokal in `UserDefaults` und nicht in CloudKit: Auf jedem iPhone
/// ist jemand anderes "ich". Der Owner wird beim Erststart gesetzt, eingeladene
/// Mitglieder wählen sich nach der Annahme einmal selbst aus.
enum CurrentMember {

    static let storageKey = "currentMemberID"
    /// Nur Anzeige: Erwachsene sehen die App vorübergehend aus Sicht eines Kindes.
    static let previewKey = "previewMemberID"

    static var id: UUID? {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: storageKey) }
    }

    static func resolve(in context: NSManagedObjectContext, household: CDHousehold) -> CDMember? {
        guard let id else { return nil }
        let members = (household.members as? Set<CDMember>) ?? []
        return members.first { $0.id == id && $0.isActive }
    }
}

// MARK: - Anzeigetexte

extension MemberRole {
    var label: String {
        switch self {
        case .adult: return "Erwachsener"
        case .child: return "Kind"
        case .guest: return "Gast"
        }
    }
}

extension MemberAccountKind {
    var label: String {
        switch self {
        case .participant: return "Eigenes iPhone"
        case .managed: return "Wird von Erwachsenen gepflegt"
        }
    }
}

extension CDMember {
    var role: MemberRole { MemberRole(rawValue: roleRaw ?? "") ?? .adult }
    var accountKind: MemberAccountKind { MemberAccountKind(rawValue: accountKindRaw ?? "") ?? .managed }
}
