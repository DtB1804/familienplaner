import CoreData
import UIKit

/// Merkt sich pro Gerät, wer es benutzt und ob das Sprachmodell auf dem Gerät
/// verfügbar ist (CLAUDE.md Regel 10: geprüft, nicht angenommen). Lokaler Store.
@MainActor
enum DeviceRegistrationService {

    static func refresh(memberID: UUID?, in context: NSManagedObjectContext) {
        let request = NSFetchRequest<CDDeviceRegistration>(entityName: "CDDeviceRegistration")
        request.fetchLimit = 1
        let registration = (try? context.fetch(request).first) ?? {
            let new = CDDeviceRegistration(context: context)
            new.id = UUID()
            new.createdAt = Date()
            return new
        }()
        registration.memberID = memberID
        registration.deviceName = UIDevice.current.model
        registration.osVersion = UIDevice.current.systemVersion
        registration.supportsOnDeviceModel = SuggestionExtractor.modelIsAvailable
        registration.lastSeenAt = Date()
        registration.updatedAt = Date()
        PersistenceController.shared.save(context)
    }
}
