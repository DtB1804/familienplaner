import CoreData
import XCTest
@testable import Familienplaner

@MainActor
final class HouseholdServiceTests: XCTestCase {

    func testBootstrapCreatesOwnerAndSystemTags() throws {
        let fx = try Fixture()
        XCTAssertEqual(fx.household.name, "Testfamilie")
        XCTAssertEqual(fx.household.ownerMemberID, fx.owner.id)
        XCTAssertEqual(fx.owner.role, .adult)
        XCTAssertEqual(fx.owner.colorToken, "person1")
        XCTAssertEqual((fx.household.tags as? Set<CDTag>)?.count, 5)
        XCTAssertTrue(fx.household.childrenSeeAdultTitles, "Voreinstellung: Kinder sehen Titel")
    }

    func testBootstrapIsIdempotent() throws {
        let fx = try Fixture()
        let again = try HouseholdService.bootstrapIfNeeded(in: fx.context, householdName: "Andere",
                                                           ownerDisplayName: "X", ownerShortName: "X")
        XCTAssertEqual(again.objectID, fx.household.objectID)
        XCTAssertEqual(try fx.context.count(for: NSFetchRequest<CDHousehold>(entityName: "CDHousehold")), 1)
        XCTAssertEqual(try fx.context.count(for: NSFetchRequest<CDMember>(entityName: "CDMember")), 1)
    }

    func testMemberShortNameIsLimitedToThreeCharacters() throws {
        let fx = try Fixture()
        let member = HouseholdService.makeMember(in: fx.context, household: fx.household, displayName: "Josephine",
                                                 shortName: "JOSE", role: .child, accountKind: .managed,
                                                 colorToken: "person2", sortIndex: 1)
        XCTAssertEqual(member.shortName, "JOS")
    }

    func testNextColorTokenSkipsUsedColors() throws {
        let fx = try Fixture()
        XCTAssertEqual(HouseholdService.nextColorToken(in: fx.context), "person2")
        fx.member("Ben")
        XCTAssertEqual(HouseholdService.nextColorToken(in: fx.context), "person3")
    }

    func testOwnHouseholdLivesInPrivateStore() throws {
        let fx = try Fixture()
        XCTAssertEqual(fx.household.objectID.persistentStore, fx.persistence.privateStore)
        XCTAssertTrue(HouseholdService.isOwner(of: fx.household, persistence: fx.persistence))
    }

    /// Regel 11: Eingeladene haben den Haushalt im geteilten Store. Neue Mitglieder,
    /// Termine und Beteiligungen müssen dort landen, sonst scheitert das Speichern.
    func testSharedHouseholdIsPreferredAndNewObjectsFollowItsStore() throws {
        let fx = try Fixture()
        let sharedStore = try XCTUnwrap(fx.persistence.sharedStore)
        let shared = CDHousehold(context: fx.context)
        fx.context.assign(shared, to: sharedStore)
        shared.id = UUID()
        shared.name = "Geteilt"
        shared.createdAt = Date().addingTimeInterval(60)
        try fx.save()

        let found = try HouseholdService.fetchHousehold(in: fx.context, persistence: fx.persistence)
        XCTAssertEqual(found?.objectID, shared.objectID)
        XCTAssertFalse(HouseholdService.isOwner(of: shared, persistence: fx.persistence))

        let ben = HouseholdService.makeMember(in: fx.context, household: shared, displayName: "Ben", shortName: "BE",
                                              role: .adult, accountKind: .participant, colorToken: "person2", sortIndex: 0)
        let event = EventService.makeEvent(in: fx.context, household: shared, title: "Geteilter Termin",
                                           startAt: Date().addingTimeInterval(3600), endAt: Date().addingTimeInterval(7200),
                                           createdBy: ben, subjects: [ben], requiredRoles: [.driveTo])
        try fx.save()
        EventService.claim(role: .driveTo, on: event, by: ben, in: fx.context)
        XCTAssertNoThrow(try fx.save())

        XCTAssertEqual(ben.objectID.persistentStore, sharedStore)
        XCTAssertEqual(event.objectID.persistentStore, sharedStore)
        for participation in (event.participations as? Set<CDEventParticipation>) ?? [] {
            XCTAssertEqual(participation.objectID.persistentStore, sharedStore)
        }
    }
}
