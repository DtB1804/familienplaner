import CloudKit
import CoreData
import XCTest
@testable import Familienplaner

/// Sicherung (.ics), iCloud-Status und Haushalt löschen.
@MainActor
final class BackupAndSyncTests: XCTestCase {

    // MARK: Kalenderdatei

    func testICSContainsTimedAndAllDayEventsWithEscaping() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        let timed = fx.event("Schwimmen; Bahn 2, Halle", subjects: [mia], roles: [.driveFrom],
                             location: "Hallenbad", notes: "Badekappe\\nHandtuch")
        EventService.claim(role: .driveFrom, on: timed, by: fx.owner, in: fx.context)
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(3 * 86_400))
        EventService.makeEvent(in: fx.context, household: fx.household, title: "Urlaub", startAt: day,
                               endAt: day.addingTimeInterval(2 * 86_400), createdBy: fx.owner,
                               subjects: [fx.owner], isAllDay: true)
        let deleted = fx.event("Gelöscht")
        EventService.softDelete(deleted)
        try fx.save()

        let events = try fx.context.fetch(ICSExporter.allEventsRequest())
        let ics = ICSExporter.calendar(events: events, viewer: fx.owner, household: fx.household)
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 2, "Gelöschtes fehlt, zwei Termine")
        XCTAssertTrue(ics.contains(#"SUMMARY:Schwimmen\; Bahn 2\, Halle"#))
        XCTAssertTrue(ics.contains("LOCATION:Hallenbad"))
        XCTAssertTrue(ics.contains("Holt: Anna"))
        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:"))
        XCTAssertTrue(ics.contains("UID:\(timed.id!.uuidString)@familyplanner"))
        for line in ics.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.utf8.count, 75, "Zeile zu lang: \(line)")
        }
    }

    func testICSBusyOnlyHidesDetails() throws {
        let fx = try Fixture()
        let shift = fx.event("Nachtdienst", visibility: .busyOnly, notes: "geheim")
        let ics = ICSExporter.calendar(events: [shift], viewer: fx.owner, household: fx.household)
        XCTAssertTrue(ics.contains("SUMMARY:Belegt"))
        XCTAssertFalse(ics.contains("geheim"))
        XCTAssertFalse(ics.contains("Nachtdienst"))
    }

    func testFoldingKeepsMultibyteCharactersIntact() {
        let long = "DESCRIPTION:" + String(repeating: "ä", count: 60)
        let folded = ICSExporter.fold(long)
        XCTAssertGreaterThan(folded.count, 1)
        XCTAssertTrue(folded.dropFirst().allSatisfy { $0.hasPrefix(" ") })
        XCTAssertEqual(folded.enumerated().map { $0.offset == 0 ? $0.element : String($0.element.dropFirst()) }.joined(), long)
        XCTAssertTrue(folded.allSatisfy { $0.utf8.count <= 75 })
    }

    // MARK: iCloud-Status

    func testSyncProblemPriorities() {
        XCTAssertNil(SyncProblem.current(accountStatus: .available, isOnline: true, lastError: nil))
        XCTAssertEqual(SyncProblem.current(accountStatus: .noAccount, isOnline: false, lastError: nil), .noAccount)
        XCTAssertEqual(SyncProblem.current(accountStatus: .available, isOnline: false, lastError: nil), .offline)
        XCTAssertEqual(SyncProblem.current(accountStatus: .available, isOnline: true,
                                           lastError: CKError(.quotaExceeded)), .quotaExceeded)
        XCTAssertEqual(SyncProblem.current(accountStatus: .available, isOnline: true,
                                           lastError: CKError(.networkUnavailable)), .offline)
        XCTAssertEqual(SyncProblem.current(accountStatus: .restricted, isOnline: true, lastError: nil), .restricted)
        if case .failed = SyncProblem.current(accountStatus: .available, isOnline: true,
                                              lastError: CKError(.serverRejectedRequest)) {} else {
            XCTFail("Sonstige Fehler als 'gestört' melden")
        }
    }

    // MARK: Haushalt entfernen

    func testRemovingHouseholdDeletesAllDataInItsStore() async throws {
        let fx = try Fixture()
        fx.member("Mia", role: .child)
        fx.event("Schwimmen", roles: [.driveTo])
        try fx.save()
        let saved = CurrentMember.id
        defer { CurrentMember.id = saved }

        try await HouseholdRemoval.remove(fx.household, persistence: fx.persistence)
        for entity in HouseholdRemoval.cloudEntities {
            XCTAssertEqual(try fx.context.count(for: NSFetchRequest<NSManagedObject>(entityName: entity)), 0, entity)
        }
    }
}
