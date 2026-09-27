import CloudKit
import CoreData
import Foundation
import UserNotifications
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Haushalt löschen (Owner) oder verlassen (Eingeladene).
///
/// In iCloud liegt ein Haushalt in einer eigenen Zone. `purgeObjectsAndRecordsInZone`
/// entfernt die Zone mit allen Datensätzen: beim Owner in der privaten Datenbank, also für
/// alle Mitglieder; bei Eingeladenen in der geteilten Datenbank, also nur auf deren Seite.
/// Dazu kommen die gerätelokalen Daten (Kalenderquellen, Erinnerungen, iPhone-Kalender,
/// Widgets, "ich"). Ohne CloudKit (Tests) werden die Objekte direkt gelöscht.
enum HouseholdRemoval {

    enum Failure: LocalizedError {
        case noStore, noZone
        var errorDescription: String? {
            switch self {
            case .noStore: return "Der Haushalt ist keinem Speicher zugeordnet."
            case .noZone: return "Die iCloud-Zone des Haushalts wurde nicht gefunden."
            }
        }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner", category: "Removal")
    static let cloudEntities = ["CDEventParticipation", "CDEvent", "CDSuggestionDraft", "CDTag", "CDMember", "CDHousehold"]
    static let localEntities = ["CDLocalEventMirror", "CDCalendarSource"]

    @MainActor
    static func remove(_ household: CDHousehold, persistence: PersistenceController = .shared) async throws {
        let context = persistence.viewContext
        guard let store = household.objectID.persistentStore else { throw Failure.noStore }
        let usesCloudKit = persistence.container.persistentStoreDescriptions
            .first { $0.url == store.url }?.cloudKitContainerOptions != nil

        if usesCloudKit {
            guard let zoneID = persistence.container.recordID(for: household.objectID)?.zoneID else { throw Failure.noZone }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                persistence.container.purgeObjectsAndRecordsInZone(with: zoneID, in: store) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
        // Vorher festhalten, was weg soll: Legt jemand gleich danach einen neuen Haushalt an,
        // bleibt der unberührt.
        let doomed = usesCloudKit ? [] : try objectIDs(entities: cloudEntities, in: store, context: context)
        let localStores = persistence.container.persistentStoreCoordinator.persistentStores
            .filter { $0.configurationName == "Local" }
        let doomedLocal = localStores.flatMap { (try? objectIDs(entities: localEntities, in: $0, context: context)) ?? [] }
        let oldMemberID = CurrentMember.id

        // Erst die Oberfläche auf "Einrichten" umstellen, dann aufräumen. Sonst greifen noch
        // sichtbare Ansichten auf bereits gelöschte Objekte zu.
        NotificationCenter.default.post(name: .householdRemoved, object: nil)
        try? await Task.sleep(for: .milliseconds(500))
        for id in doomed + doomedLocal {
            if let object = try? context.existingObject(with: id) { context.delete(object) }
        }
        if context.hasChanges { try? context.save() }
        if usesCloudKit { context.reset() }
        await cleanUpDevice(oldMemberID: oldMemberID)
        logger.info("Haushalt entfernt")
    }

    static func objectIDs(entities: [String], in store: NSPersistentStore,
                          context: NSManagedObjectContext) throws -> [NSManagedObjectID] {
        var ids: [NSManagedObjectID] = []
        for entity in entities where context.persistentStoreCoordinator?.managedObjectModel.entitiesByName[entity] != nil {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: entity)
            request.resultType = .managedObjectIDResultType
            request.affectedStores = [store]
            ids += try context.fetch(request)
        }
        return ids
    }

    /// Alles, was nur auf diesem Gerät liegt.
    @MainActor
    private static func cleanUpDevice(oldMemberID: UUID?) async {
        let defaults = UserDefaults.standard
        if CurrentMember.id == oldMemberID { CurrentMember.id = nil }
        for key in defaults.dictionaryRepresentation().keys
        where key == CurrentMember.previewKey || key.hasPrefix("reminders.") || key.hasPrefix("onboarding.") {
            defaults.removeObject(forKey: key)
        }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier)
            .filter { $0.hasPrefix(ReminderService.identifierPrefix) })
        if CalendarExportService.scope != .off {
            CalendarExportService.shared.removeAll()
            CalendarExportService.scope = .off
        }
        if let url = WidgetBridge.fileURL { try? FileManager.default.removeItem(at: url) }
        while SharedInbox.takeNext() != nil {}
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

extension Notification.Name {
    /// Haushalt gelöscht oder verlassen: zurück zur Einrichtung.
    static let householdRemoved = Notification.Name("householdRemoved")
}
