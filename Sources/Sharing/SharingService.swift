import CoreData
import CloudKit
import UIKit
import os

/// Teilen des Haushalts über CloudKit.
///
/// Geteilt wird genau ein Objekt: der `CDHousehold`. `NSPersistentCloudKitContainer`
/// nimmt alles mit, was über Beziehungen daran hängt (Mitglieder, Termine,
/// Beteiligungen, Kategorien). Kalenderquellen und Spiegel liegen im lokalen Store
/// und werden nie geteilt (CLAUDE.md, Regel 3).
@MainActor
public enum SharingService {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                       category: "Sharing")

    /// Vorhandene Freigabe des Haushalts, falls schon einmal eingeladen wurde.
    public static func existingShare(for household: CDHousehold,
                                     persistence: PersistenceController = .shared) -> CKShare? {
        do {
            let shares = try persistence.container.fetchShares(matching: [household.objectID])
            return shares[household.objectID]
        } catch {
            logger.error("Freigabe konnte nicht gelesen werden: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Liefert die vorhandene Freigabe oder legt eine neue an.
    public static func shareForHousehold(_ household: CDHousehold,
                                         persistence: PersistenceController = .shared) async throws -> CKShare {
        if let share = existingShare(for: household, persistence: persistence) {
            return share
        }
        let (_, share, _) = try await persistence.container.share([household], to: nil)
        share[CKShare.SystemFieldKey.title] = (household.name ?? "Familie") as CKRecordValue
        // Nur ausdrücklich eingeladene Personen, kein Zugriff per weitergeleitetem Link.
        share.publicPermission = .none
        return share
    }

    /// Öffnet Apples Einladungsdialog (Nachrichten, Mail, Link kopieren).
    public static func presentInvitation(for household: CDHousehold,
                                         persistence: PersistenceController = .shared) async throws {
        let share = try await shareForHousehold(household, persistence: persistence)
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)

        let controller = UICloudSharingController(share: share, container: ckContainer)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        let delegate = SharingControllerDelegate(title: household.name ?? "Familie")
        activeDelegate = delegate          // UICloudSharingController hält seinen Delegate nur schwach
        controller.delegate = delegate
        controller.modalPresentationStyle = .formSheet

        guard let presenter = topViewController() else {
            logger.error("Kein sichtbarer View Controller für den Einladungsdialog")
            return
        }
        presenter.present(controller, animated: true)
    }

    /// Teilnehmer der Freigabe ohne den Owner, für die Anzeige in der Mitgliederliste.
    public static func participants(of share: CKShare) -> [CKShare.Participant] {
        share.participants.filter { $0.role != .owner }
    }

    // MARK: - Intern

    private static var activeDelegate: SharingControllerDelegate?

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private final class SharingControllerDelegate: NSObject, UICloudSharingControllerDelegate {

    private let title: String
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                category: "Sharing")

    init(title: String) { self.title = title }

    func itemTitle(for csc: UICloudSharingController) -> String? { title }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        logger.error("Freigabe konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        NotificationCenter.default.post(name: .householdShareChanged, object: nil)
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        // Der Owner behält seine Daten im privaten Store. Die anderen Geräte
        // verlieren den Zugriff; ihre Kopie räumt CloudKit beim nächsten Sync ab.
        NotificationCenter.default.post(name: .householdShareChanged, object: nil)
    }
}

public extension Notification.Name {
    /// Einladung auf diesem Gerät angenommen; der Haushalt kommt per Sync nach.
    static let householdShareAccepted = Notification.Name("householdShareAccepted")
    /// Teilnehmer hinzugefügt, entfernt oder Freigabe beendet.
    static let householdShareChanged = Notification.Name("householdShareChanged")
}
