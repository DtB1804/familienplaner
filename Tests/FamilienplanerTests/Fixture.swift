import CoreData
import XCTest
@testable import Familienplaner

/// Frischer Haushalt in einem eigenen Arbeitsspeicher-Stack (drei Stores wie in der App,
/// ohne iCloud). Jeder Test bekommt seinen eigenen, nichts bleibt zwischen Tests liegen.
@MainActor
final class Fixture {
    let persistence = PersistenceController(inMemory: true)
    var context: NSManagedObjectContext { persistence.viewContext }
    let household: CDHousehold
    let owner: CDMember

    init() throws {
        household = try HouseholdService.bootstrapIfNeeded(in: persistence.viewContext,
                                                           householdName: "Testfamilie",
                                                           ownerDisplayName: "Anna",
                                                           ownerShortName: "AN")
        let members = (household.members as? Set<CDMember>) ?? []
        owner = try XCTUnwrap(members.first)
    }

    @discardableResult
    func member(_ name: String, role: MemberRole = .adult) -> CDMember {
        HouseholdService.makeMember(in: context, household: household,
                                    displayName: name, shortName: String(name.prefix(2)),
                                    role: role, accountKind: .managed,
                                    colorToken: HouseholdService.nextColorToken(in: context),
                                    sortIndex: 1)
    }

    /// Termin relativ zu jetzt, Angaben in Stunden.
    @discardableResult
    func event(_ title: String, inHours start: Double = 24, length: Double = 1,
               subjects: [CDMember]? = nil, roles: [ParticipationRole] = [],
               visibility: EventVisibility = .household,
               location: String? = nil, notes: String? = nil) -> CDEvent {
        let from = Date().addingTimeInterval(start * 3600)
        return EventService.makeEvent(in: context, household: household, title: title,
                                      startAt: from, endAt: from.addingTimeInterval(length * 3600),
                                      createdBy: owner, subjects: subjects ?? [owner],
                                      requiredRoles: roles, visibility: visibility,
                                      locationName: location, notes: notes)
    }

    func save() throws { try context.save() }

    func count(_ request: NSFetchRequest<CDEvent>) throws -> Int { try context.count(for: request) }
}
