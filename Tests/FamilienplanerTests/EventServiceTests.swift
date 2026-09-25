import CoreData
import XCTest
@testable import Familienplaner

@MainActor
final class EventServiceTests: XCTestCase {

    // MARK: Projektionsprinzip (Regel 2)

    func testBusyOnlyNeverStoresTitleLocationOrNotes() throws {
        let fx = try Fixture()
        let event = fx.event("Dienst Station 4", visibility: .busyOnly, location: "Klinik", notes: "Übergabe")
        try fx.save()
        fx.context.refreshAllObjects()
        XCTAssertEqual(event.title, "Belegt")
        XCTAssertNil(event.locationName)
        XCTAssertNil(event.notes)
        XCTAssertEqual(try fx.count(EventService.searchRequest("Station")), 0, "Originaltitel darf nicht auffindbar sein")
    }

    func testEmptyLocationAndNotesAreStoredAsNil() throws {
        let fx = try Fixture()
        let event = fx.event("Schwimmen", location: "", notes: "")
        XCTAssertNil(event.locationName)
        XCTAssertNil(event.notes)
    }

    func testUpdateToBusyOnlyStripsExistingDetails() throws {
        let fx = try Fixture()
        let event = fx.event("Arzt", location: "Praxis", notes: "Karte mitbringen")
        EventService.update(event, in: fx.context, title: "Arzt", startAt: event.startAt!, endAt: event.endAt!,
                            subjects: [fx.owner], requiredRoles: [], kind: .appointment,
                            visibility: .busyOnly, tag: nil, locationName: "Praxis", notes: "Karte mitbringen")
        XCTAssertEqual(event.title, "Belegt")
        XCTAssertNil(event.locationName)
        XCTAssertNil(event.notes)
    }

    // MARK: Ändern

    func testUpdateSyncsSubjectsButKeepsResponsibilities() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        let tom = fx.member("Tom", role: .child)
        let event = fx.event("Schwimmen", subjects: [fx.owner, mia], roles: [.driveFrom])
        XCTAssertEqual(EventService.claim(role: .driveFrom, on: event, by: fx.owner, in: fx.context), .claimed)

        EventService.update(event, in: fx.context, title: "Schwimmen", startAt: event.startAt!, endAt: event.endAt!,
                            subjects: [mia, tom], requiredRoles: [.driveFrom], kind: .appointment,
                            visibility: .household, tag: nil, locationName: nil, notes: nil)
        try fx.save()

        XCTAssertEqual(Set(EventService.subjects(of: event).compactMap(\.displayName)), ["Mia", "Tom"])
        XCTAssertEqual(EventService.coveredRoles(of: event), [.driveFrom], "Übernommene Zuständigkeit muss bleiben")
    }

    // MARK: Weiches Löschen (Regel 6)

    func testSoftDeleteHidesEverywhereButKeepsRecord() throws {
        let fx = try Fixture()
        let event = fx.event("Elternabend", inHours: 1, roles: [.accompany])
        try fx.save()
        let day = event.startAt!
        XCTAssertEqual(try fx.count(EventService.eventsRequest(on: day)), 1)

        EventService.softDelete(event)
        try fx.save()

        XCTAssertEqual(try fx.count(EventService.eventsRequest(on: day)), 0)
        XCTAssertEqual(try fx.count(EventService.searchRequest("Eltern")), 0)
        XCTAssertTrue(try EventService.openResponsibilities(in: fx.context).isEmpty)
        XCTAssertEqual(try fx.context.count(for: NSFetchRequest<CDEvent>(entityName: "CDEvent")), 1)
        XCTAssertNotNil(event.deletedAt)
    }

    // MARK: Abfragen

    func testEventsRequestIncludesOverlapsAndExcludesTouchingEvents() throws {
        let fx = try Fixture()
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: Date()))!
        func make(_ title: String, _ from: Date, _ to: Date) {
            EventService.makeEvent(in: fx.context, household: fx.household, title: title,
                                   startAt: from, endAt: to, createdBy: fx.owner)
        }
        make("über Mitternacht", day.addingTimeInterval(-1800), day.addingTimeInterval(1800))
        make("endet genau um 0 Uhr", day.addingTimeInterval(-3600), day)
        make("mittags", day.addingTimeInterval(12 * 3600), day.addingTimeInterval(13 * 3600))
        make("nächster Tag 0 Uhr", day.addingTimeInterval(24 * 3600), day.addingTimeInterval(25 * 3600))
        try fx.save()

        let titles = try fx.context.fetch(EventService.eventsRequest(on: day)).compactMap(\.title)
        XCTAssertEqual(Set(titles), ["über Mitternacht", "mittags"])
    }

    func testSearchIgnoresCaseAndDiacriticsAndCoversLocationAndNotes() throws {
        let fx = try Fixture()
        fx.event("Schwimmen", location: "Hallenbad Nord")
        fx.event("Übung Feuerwehr", notes: "Hasenweg 3")
        try fx.save()
        XCTAssertEqual(try fx.count(EventService.searchRequest("SCHWIMM")), 1)
        XCTAssertEqual(try fx.count(EventService.searchRequest("hallenbad")), 1)
        XCTAssertEqual(try fx.count(EventService.searchRequest("ubung")), 1)
        XCTAssertEqual(try fx.count(EventService.searchRequest("hasenweg")), 1)
        XCTAssertEqual(try fx.count(EventService.searchRequest("Tennis")), 0)
    }

    // MARK: Zuständigkeiten (Regel 5)

    func testOpenResponsibilitiesAreDifferenceOfRequiredAndCovered() throws {
        let fx = try Fixture()
        let event = fx.event("Fußball", roles: [.driveTo, .driveFrom])
        try fx.save()
        XCTAssertEqual(Set(try EventService.openResponsibilities(in: fx.context).map(\.role)), [.driveTo, .driveFrom])

        EventService.claim(role: .driveTo, on: event, by: fx.owner, in: fx.context)
        let open = try EventService.openResponsibilities(in: fx.context)
        XCTAssertEqual(open.map(\.role), [.driveFrom])
        XCTAssertEqual(open.first?.eventTitle, "Fußball")
    }

    func testOpenResponsibilitiesRespectTimeWindow() throws {
        let fx = try Fixture()
        fx.event("gestern", inHours: -24, roles: [.driveTo])
        fx.event("in 20 Tagen", inHours: 24 * 20, roles: [.driveTo])
        fx.event("in 2 Tagen", inHours: 48, roles: [.driveTo])
        try fx.save()
        XCTAssertEqual(try EventService.openResponsibilities(in: fx.context).map(\.eventTitle), ["in 2 Tagen"])
        XCTAssertEqual(try EventService.openResponsibilities(within: 1, in: fx.context).count, 0)
        XCTAssertEqual(try EventService.openResponsibilities(within: 30, in: fx.context).count, 2)
    }

    func testSecondAdultCannotClaimTakenRole() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        let event = fx.event("Schwimmen", roles: [.driveFrom])
        XCTAssertEqual(EventService.claim(role: .driveFrom, on: event, by: fx.owner, in: fx.context), .claimed)
        XCTAssertEqual(EventService.claim(role: .driveFrom, on: event, by: ben, in: fx.context), .alreadyTaken(by: "Anna"))
        let participations = (event.participations as? Set<CDEventParticipation>) ?? []
        XCTAssertEqual(participations.filter { $0.roleRaw == "driveFrom" }.count, 1, "Abgelehnter Claim darf nichts anlegen")
    }

    func testDeclinedParticipationReopensRole() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        let event = fx.event("Schwimmen", roles: [.driveFrom])
        EventService.addParticipation(in: fx.context, event: event, member: fx.owner, role: .driveFrom, status: .declined)
        try fx.save()
        XCTAssertEqual(try EventService.openResponsibilities(in: fx.context).map(\.role), [.driveFrom])
        XCTAssertEqual(EventService.claim(role: .driveFrom, on: event, by: ben, in: fx.context), .claimed)
    }

    func testConcurrentClaimsResolveDeterministically() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        let event = fx.event("Schwimmen", roles: [.driveFrom])
        let a = EventService.addParticipation(in: fx.context, event: event, member: fx.owner, role: .driveFrom)
        let b = EventService.addParticipation(in: fx.context, event: event, member: ben, role: .driveFrom)
        let stamp = Date()

        // Früherer Zeitstempel gewinnt, unabhängig von der UUID.
        a.id = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")
        b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")
        a.claimedAt = stamp
        b.claimedAt = stamp.addingTimeInterval(1)
        XCTAssertEqual(EventService.earliest(of: [a, b]), a)
        XCTAssertEqual(EventService.earliest(of: [b, a]), a)

        // Gleichstand: kleinere UUID gewinnt, auf jedem Gerät gleich.
        b.claimedAt = stamp
        XCTAssertEqual(EventService.earliest(of: [a, b]), b)
        XCTAssertEqual(EventService.earliest(of: [b, a]), b)
        XCTAssertNil(EventService.earliest(of: [CDEventParticipation]()))
    }

    // MARK: Kodierung

    func testRequiredRolesRoundTrip() {
        let roles: [ParticipationRole] = [.driveTo, .driveFrom, .accompany]
        XCTAssertEqual(RequiredRoles.encode(roles), "driveTo,driveFrom,accompany")
        XCTAssertEqual(RequiredRoles.decode(RequiredRoles.encode(roles)), roles)
        XCTAssertEqual(RequiredRoles.decode(nil), [])
        XCTAssertEqual(RequiredRoles.decode(""), [])
        XCTAssertEqual(RequiredRoles.decode("driveTo,unbekannt"), [.driveTo])
    }

    func testDefaultDurationIsThirtyMinutes() {
        XCTAssertEqual(EventService.defaultDuration, 30 * 60)
    }
}
