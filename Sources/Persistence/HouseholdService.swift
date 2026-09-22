import CoreData
import Foundation

/// Alles, was den Haushalt und seine Mitglieder betrifft.
public enum HouseholdService {

    // MARK: - Einrichtung

    /// Legt beim ersten Start genau einen Haushalt mit dem ersten Erwachsenen an.
    /// Idempotent: ein zweiter Aufruf liefert den vorhandenen Haushalt zurück.
    @discardableResult
    public static func bootstrapIfNeeded(in context: NSManagedObjectContext,
                                         householdName: String,
                                         ownerDisplayName: String,
                                         ownerShortName: String) throws -> CDHousehold {
        if let existing = try fetchHousehold(in: context) { return existing }

        let now = Date()
        let household = CDHousehold(context: context)
        household.id = UUID()
        household.name = householdName
        household.timeZoneIdentifier = TimeZone.current.identifier
        household.weekStartsOn = 1
        household.schemaVersion = 1
        household.createdAt = now
        household.updatedAt = now

        let owner = makeMember(in: context,
                               household: household,
                               displayName: ownerDisplayName,
                               shortName: ownerShortName,
                               role: .adult,
                               accountKind: .participant,
                               colorToken: Palette.personTokens[0],
                               sortIndex: 0)
        household.ownerMemberID = owner.id

        for (index, preset) in TagPreset.systemTags.enumerated() {
            let tag = CDTag(context: context)
            tag.id = UUID()
            tag.household = household
            tag.name = preset.name
            tag.colorToken = preset.colorToken
            tag.symbolName = preset.symbolName
            tag.isSystem = true
            tag.sortIndex = Int16(index)
            tag.createdAt = now
            tag.updatedAt = now
        }

        try context.save()
        return household
    }

    /// Liefert den Haushalt dieses Geräts.
    ///
    /// Ein geteilter Haushalt (Einladung angenommen) hat Vorrang vor einem eigenen.
    /// Das deckt den Fall ab, dass jemand die App erst selbst eingerichtet und danach
    /// die Einladung angenommen hat.
    public static func fetchHousehold(in context: NSManagedObjectContext,
                                      persistence: PersistenceController = .shared) throws -> CDHousehold? {
        let request = NSFetchRequest<CDHousehold>(entityName: "CDHousehold")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let all = try context.fetch(request)
        if let sharedStore = persistence.sharedStore,
           let shared = all.first(where: { $0.objectID.persistentStore == sharedStore }) {
            return shared
        }
        return all.first
    }

    /// Owner ist, wer den Haushalt im privaten Store hat. Nur der Owner kann einladen.
    public static func isOwner(of household: CDHousehold,
                               persistence: PersistenceController = .shared) -> Bool {
        guard let store = household.objectID.persistentStore else { return true }
        return store != persistence.sharedStore
    }

    // MARK: - Mitglieder

    @discardableResult
    public static func makeMember(in context: NSManagedObjectContext,
                                  household: CDHousehold,
                                  displayName: String,
                                  shortName: String,
                                  role: MemberRole,
                                  accountKind: MemberAccountKind,
                                  colorToken: String,
                                  sortIndex: Int) -> CDMember {
        let now = Date()
        let member = CDMember(context: context)
        PersistenceController.assign(member, toStoreOf: household)
        member.id = UUID()
        member.household = household
        member.displayName = displayName
        member.shortName = String(shortName.prefix(3))
        member.roleRaw = role.rawValue
        member.accountKindRaw = accountKind.rawValue
        member.colorToken = colorToken
        member.isActive = true
        member.sortIndex = Int16(sortIndex)
        member.createdAt = now
        member.updatedAt = now
        return member
    }

    public static func activeMembersRequest() -> NSFetchRequest<CDMember> {
        let request = NSFetchRequest<CDMember>(entityName: "CDMember")
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortIndex", ascending: true),
            NSSortDescriptor(key: "displayName", ascending: true)
        ]
        return request
    }

    /// Nächster freier Farb-Token, damit zwei Mitglieder nie dieselbe Farbe bekommen.
    public static func nextColorToken(in context: NSManagedObjectContext) -> String {
        let used = (try? context.fetch(activeMembersRequest()).compactMap(\.colorToken)) ?? []
        return Palette.personTokens.first { !used.contains($0) } ?? Palette.personTokens[0]
    }
}

// MARK: - Vorgegebene Kategorien

public struct TagPreset {
    public let name: String
    public let colorToken: String
    public let symbolName: String

    public static let systemTags: [TagPreset] = [
        TagPreset(name: "Schule",  colorToken: "tagSchool",  symbolName: "backpack"),
        TagPreset(name: "Sport",   colorToken: "tagSport",   symbolName: "figure.run"),
        TagPreset(name: "Arzt",    colorToken: "tagHealth",  symbolName: "cross.case"),
        TagPreset(name: "Arbeit",  colorToken: "tagWork",    symbolName: "briefcase"),
        TagPreset(name: "Privat",  colorToken: "tagPrivate", symbolName: "house")
    ]
}
