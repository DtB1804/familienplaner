import CoreData
import CloudKit
import os

/// Aufbau des Core-Data-Stacks mit drei Stores:
///
///  1. `private.sqlite`  – Cloud-Konfiguration, CloudKit-Scope `.private`
///                         Hier liegen die Daten des Haushalts-Owners.
///  2. `shared.sqlite`   – Cloud-Konfiguration, CloudKit-Scope `.shared`
///                         Hier landen die Daten, die andere mit mir geteilt haben.
///  3. `local.sqlite`    – Local-Konfiguration, kein CloudKit
///                         Kalenderquellen, Spiegel und Geräteregistrierung.
///
/// Warum drei: Beziehungen können in Core Data keine Store-Grenzen überschreiten.
/// Deshalb verweisen die lokalen Entitäten über UUID-Felder auf die Cloud-Entitäten
/// und nicht über Relationships. Das ist Absicht, kein Versäumnis.
public final class PersistenceController {

    public static let shared = PersistenceController()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                       category: "Persistence")

    /// Muss mit dem Container im Apple-Developer-Portal übereinstimmen.
    /// Siehe AUFGABEN-DAVID.md, Aufgabe 3.
    public static let cloudKitContainerIdentifier = "iCloud.de.barg.familienplaner"

    public let container: NSPersistentCloudKitContainer

    /// Nur für Previews und Tests: alles im Arbeitsspeicher, kein CloudKit.
    public static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        SampleData.populate(in: controller.container.viewContext)
        return controller
    }()

    public init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Familienplaner")

        let baseURL = inMemory
            ? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            : NSPersistentContainer.defaultDirectoryURL()

        // MARK: Store 1 – private Cloud-Datenbank
        let privateDescription = NSPersistentStoreDescription(
            url: baseURL.appendingPathComponent("private.sqlite"))
        privateDescription.configuration = "Cloud"

        // MARK: Store 2 – geteilte Cloud-Datenbank
        let sharedDescription = NSPersistentStoreDescription(
            url: baseURL.appendingPathComponent("shared.sqlite"))
        sharedDescription.configuration = "Cloud"

        // MARK: Store 3 – rein lokal, niemals synchronisiert
        let localDescription = NSPersistentStoreDescription(
            url: baseURL.appendingPathComponent("local.sqlite"))
        localDescription.configuration = "Local"
        localDescription.cloudKitContainerOptions = nil

        if inMemory {
            [privateDescription, sharedDescription, localDescription].forEach {
                $0.type = NSInMemoryStoreType
            }
            container.persistentStoreDescriptions = [privateDescription, sharedDescription, localDescription]
        } else {
            let privateOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions

            let sharedOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions

            // Beide Cloud-Stores brauchen History Tracking und Remote-Change-Notifications,
            // sonst merkt die App nichts von Änderungen anderer Geräte.
            for description in [privateDescription, sharedDescription] {
                description.setOption(true as NSNumber,
                                      forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber,
                                      forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }

            container.persistentStoreDescriptions = [privateDescription, sharedDescription, localDescription]
        }

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                // Bewusst kein fatalError im Auslieferungsstand: ein defekter
                // Store darf die App nicht beim Start töten, sonst ist sie
                // für die Familie unbenutzbar und nicht mehr reparierbar.
                Self.logger.error("Store \(description.url?.lastPathComponent ?? "?") konnte nicht geladen werden: \(error, privacy: .public)")
                #if DEBUG
                assertionFailure("Store konnte nicht geladen werden: \(error)")
                #endif
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "viewContext"

        #if DEBUG
        // Einmalig aktivieren, um das CloudKit-Schema aus dem Modell zu erzeugen.
        // Danach wieder auskommentieren. Siehe AUFGABEN-DAVID.md, Aufgabe 10.
        // try? container.initializeCloudKitSchema(options: [])
        #endif
    }

    // MARK: - Stores

    /// Store mit den eigenen Daten. Wer den Haushalt hier hat, ist dessen Owner.
    public var privateStore: NSPersistentStore? { store(named: "private.sqlite") }

    /// Store mit Daten, die andere mit diesem Gerät geteilt haben.
    public var sharedStore: NSPersistentStore? { store(named: "shared.sqlite") }

    private func store(named fileName: String) -> NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first {
            $0.url?.lastPathComponent == fileName
        }
    }

    /// Legt ein neues Objekt in denselben Store wie sein Bezugsobjekt.
    ///
    /// Pflicht für jedes neue Objekt, das an einem Haushalt hängt: Core Data kann
    /// keine Beziehungen über Store-Grenzen speichern. Ohne diese Zuordnung landet
    /// ein neues Objekt im ersten passenden Store (privat), während der Haushalt
    /// eines eingeladenen Mitglieds im geteilten Store liegt – das Speichern schlägt
    /// dann fehl. Ist das Bezugsobjekt selbst noch ungespeichert, entscheidet Core Data.
    public static func assign(_ object: NSManagedObject, toStoreOf anchor: NSManagedObject) {
        guard let context = object.managedObjectContext,
              object.objectID.isTemporaryID,
              let store = anchor.objectID.persistentStore else { return }
        context.assign(object, to: store)
    }

    // MARK: - Kontexte

    public var viewContext: NSManagedObjectContext { container.viewContext }

    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    /// Speichert nur, wenn es etwas zu speichern gibt, und schluckt keine Fehler still.
    @discardableResult
    public func save(_ context: NSManagedObjectContext? = nil) -> Bool {
        let context = context ?? viewContext
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            Self.logger.error("Speichern fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            return false
        }
    }
}
