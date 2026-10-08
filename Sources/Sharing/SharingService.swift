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
        // Geänderte Freigabe selbst speichern, bevor Apples Dialog sie bekommt. Scheitert das,
        // zeigt die App den CloudKit-Fehler an. Apples Dialog meldete nur "Es konnte kein Link
        // zum Teilen erstellt werden" (Familientest 01.10.2026).
        guard let store = persistence.privateStore else { return share }
        return try await persistence.container.persistUpdatedShare(share, in: store)
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

    /// Fehlertext mit CloudKit-Fehlercode, damit ein Screenshot die Ursache zeigt
    /// (Test 01.10.2026: "Einladung konnte nicht erstellt werden" ohne Details).
    nonisolated public static func describe(_ error: Error) -> String {
        var lines = [error.localizedDescription]
        if let ck = error as? CKError {
            lines.append("CloudKit-Code \(ck.code.rawValue) (\(String(describing: ck.code)))")
            if let partial = ck.partialErrorsByItemID {
                for (item, sub) in partial.prefix(3) {
                    let code = (sub as? CKError).map { "\($0.code.rawValue)" } ?? "?"
                    lines.append("• \(item): Code \(code) – \(sub.localizedDescription)")
                }
            }
            if let reason = ck.userInfo[NSLocalizedFailureReasonErrorKey] as? String { lines.append(reason) }
        } else {
            let ns = error as NSError
            lines.append("\(ns.domain) \(ns.code)")
        }
        return lines.joined(separator: "\n")
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
        // Apples Dialog schließen, sonst kann die App ihre Meldung nicht darüber zeigen.
        DispatchQueue.main.async { csc.presentingViewController?.dismiss(animated: true) }
        logger.error("Freigabe konnte nicht gespeichert werden: \(error.localizedDescription, privacy: .public)")
        // Kann außerhalb des Hauptthreads kommen. MainActor.assumeIsolated hat dann die
        // App beendet (Absturz beim Einladen, Build 39). Deshalb Text sofort bilden und
        // die Meldung auf dem Hauptthread verschicken.
        let text = SharingService.describe(error)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .householdShareFailed, object: text)
        }
    }

    // Beide Rückrufe können außerhalb des Hauptthreads kommen. Die Meldung löst in
    // MembersScreen eine Änderung der Oberfläche aus, deshalb immer auf dem Hauptthread
    // (Absturz beim Einladen, Familientest 08.10.2026).
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .householdShareChanged, object: nil)
        }
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        // Der Owner behält seine Daten im privaten Store. Die anderen Geräte
        // verlieren den Zugriff; ihre Kopie räumt CloudKit beim nächsten Sync ab.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .householdShareChanged, object: nil)
        }
    }
}

public extension Notification.Name {
    /// Einladung auf diesem Gerät angenommen; der Haushalt kommt per Sync nach.
    static let householdShareAccepted = Notification.Name("householdShareAccepted")
    /// Teilnehmer hinzugefügt, entfernt oder Freigabe beendet.
    static let householdShareChanged = Notification.Name("householdShareChanged")
    /// Apples Einladungsdialog konnte die Freigabe nicht speichern; `object` ist der Fehlertext.
    static let householdShareFailed = Notification.Name("householdShareFailed")
}
