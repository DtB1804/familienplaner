import CoreData
import XCTest
@testable import Familienplaner

/// Eintrag in den iPhone-Kalender: was eingetragen wird und wie es aussieht.
/// Der eigentliche Zugriff auf EventKit braucht eine Freigabe und läuft nur auf Geräten.
@MainActor
final class CalendarExportTests: XCTestCase {

    func testScopeDecidesWhichEventsAreExported() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        let mia = fx.member("Mia", role: .child)
        let mine = fx.event("Arzt")
        let others = fx.event("Turnen", subjects: [mia], roles: [.driveTo])
        let claimed = fx.event("Fußball", subjects: [mia], roles: [.driveFrom])
        EventService.claim(role: .driveFrom, on: claimed, by: fx.owner, in: fx.context)
        let deleted = fx.event("Weg")
        EventService.softDelete(deleted)
        let benOnly = fx.event("Ben allein", subjects: [ben])

        func export(_ event: CDEvent, _ scope: CalendarExportService.Scope) -> Bool {
            CalendarExportService.shouldExport(event, me: fx.owner, scope: scope, ownSourceIDs: [], joinedEventIDs: [])
        }
        XCTAssertTrue(export(mine, .mine))
        XCTAssertFalse(export(others, .mine))
        XCTAssertTrue(export(claimed, .mine), "Übernommene Zuständigkeit gehört zu meinen Terminen")
        XCTAssertFalse(export(benOnly, .mine))
        XCTAssertTrue(export(others, .all))
        XCTAssertTrue(export(benOnly, .all))
        XCTAssertFalse(export(deleted, .all))
        XCTAssertFalse(export(mine, .off))
    }

    func testOwnImportedEventsAreNotExportedAgain() throws {
        let fx = try Fixture()
        let sourceID = UUID()
        let imported = fx.event("Dienst", visibility: .busyOnly)
        imported.originRaw = EventOrigin.imported.rawValue
        imported.sourceCalendarSourceID = sourceID
        let joined = fx.event("Elternabend")
        XCTAssertFalse(CalendarExportService.shouldExport(imported, me: fx.owner, scope: .all,
                                                          ownSourceIDs: [sourceID], joinedEventIDs: []))
        XCTAssertFalse(CalendarExportService.shouldExport(joined, me: fx.owner, scope: .all,
                                                          ownSourceIDs: [], joinedEventIDs: [joined.id!]))
    }

    func testContentShowsPeopleDutiesAndOpenRoles() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        let mia = fx.member("Mia", role: .child)
        let event = fx.event("Schwimmen", subjects: [mia], roles: [.driveTo, .driveFrom], location: "Hallenbad", notes: "Badekappe")
        EventService.claim(role: .driveFrom, on: event, by: ben, in: fx.context)

        let forAnna = CalendarExportService.content(for: event, me: fx.owner, household: fx.household)
        XCTAssertEqual(forAnna.title, "Schwimmen (Mia)")
        XCTAssertEqual(forAnna.location, "Hallenbad")
        XCTAssertTrue(forAnna.notes.contains("Für: Mia"))
        XCTAssertTrue(forAnna.notes.contains("Holt: Ben"))
        XCTAssertTrue(forAnna.notes.contains("Noch offen: Bringt"))
        XCTAssertTrue(forAnna.notes.contains("Badekappe"))

        let forBen = CalendarExportService.content(for: event, me: ben, household: fx.household)
        XCTAssertEqual(forBen.title, "Holt Mia · Schwimmen")
    }

    func testContentRespectsBusyOnlyAndChildView() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        let shift = fx.event("Nachtdienst", visibility: .busyOnly, notes: "geheim")
        let forAnna = CalendarExportService.content(for: shift, me: fx.owner, household: fx.household)
        XCTAssertEqual(forAnna.title, "Belegt")
        XCTAssertFalse(forAnna.notes.contains("geheim"))

        fx.household.childrenSeeAdultTitles = false
        let dentist = fx.event("Zahnarzt", location: "Praxis")
        let forMia = CalendarExportService.content(for: dentist, me: mia, household: fx.household)
        XCTAssertTrue(forMia.title.hasPrefix("Belegt"))
        XCTAssertNil(forMia.location)
    }
}
