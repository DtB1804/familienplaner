import CoreData
import XCTest
@testable import Familienplaner

/// Terminserien (CLAUDE.md Regel 16).
@MainActor
final class SeriesTests: XCTestCase {

    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Regel

    func testEncodingRoundTrip() {
        for choice in RepeatChoice.allCases where choice != .none {
            let rule = choice.rule(startingAt: date(2026, 10, 31), until: date(2027, 3, 1), calendar: berlin)!
            let parsed = Recurrence(encoded: rule.encoded)
            XCTAssertEqual(parsed?.frequency, rule.frequency, choice.label)
            XCTAssertEqual(parsed?.interval, rule.interval, choice.label)
            XCTAssertEqual(parsed?.monthDay, rule.monthDay, choice.label)
            XCTAssertEqual(RepeatChoice(parsed), choice)
            XCTAssertTrue(Calendar.current.isDate(parsed!.until!, inSameDayAs: rule.until!))
        }
        XCTAssertEqual(Recurrence(frequency: .weekdays).encoded, "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR")
        XCTAssertEqual(Recurrence(frequency: .weekly, interval: 2).encoded, "FREQ=WEEKLY;INTERVAL=2")
        XCTAssertNil(Recurrence(encoded: nil))
        XCTAssertNil(Recurrence(encoded: "FREQ=SECONDLY"))
        XCTAssertNil(Recurrence(encoded: "Unsinn"))
    }

    func testWeeklyKeepsWallClockTimeAcrossDaylightSavingChange() {
        // Zeitumstellung 25.10.2026
        let next = Recurrence(frequency: .weekly).next(after: date(2026, 10, 20, 17, 30), calendar: berlin)!
        XCTAssertEqual(berlin.dateComponents([.day, .hour, .minute], from: next), DateComponents(day: 27, hour: 17, minute: 30))
    }

    func testWeekdaysSkipWeekend() {
        let friday = date(2026, 10, 2)
        let next = Recurrence(frequency: .weekdays).next(after: friday, calendar: berlin)!
        XCTAssertEqual(berlin.component(.weekday, from: next), 2, "Freitag → Montag")
        XCTAssertEqual(berlin.component(.day, from: next), 5)
    }

    func testMonthlyOnThe31stUsesLastDayOfShortMonths() {
        let rule = Recurrence(frequency: .monthly, monthDay: 31)
        let dates = rule.occurrences(after: date(2027, 1, 31), through: date(2027, 5, 31, 23), calendar: berlin)
        XCTAssertEqual(dates.map { berlin.component(.day, from: $0) }, [28, 31, 30, 31])
    }

    func testYearlyOnLeapDay() {
        let next = Recurrence(frequency: .yearly, monthDay: 29).next(after: date(2028, 2, 29), calendar: berlin)!
        XCTAssertEqual(berlin.dateComponents([.year, .month, .day], from: next), DateComponents(year: 2029, month: 2, day: 28))
    }

    func testUntilIsInclusive() {
        let rule = Recurrence(frequency: .daily, until: date(2026, 10, 5, 0))
        let dates = rule.occurrences(after: date(2026, 10, 1, 18), through: date(2027, 1, 1), calendar: berlin)
        XCTAssertEqual(dates.map { berlin.component(.day, from: $0) }, [2, 3, 4, 5])
    }

    // MARK: Serie anlegen

    func testWeeklySeriesCopiesContentForTwentySixWeeks() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        let first = fx.event("Schwimmen", inHours: 1, subjects: [mia], roles: [.driveFrom], location: "Hallenbad")
        let created = SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly), in: fx.context)
        try fx.save()

        XCTAssertEqual(created.count, SeriesService.horizonWeeks - 1)
        let all = SeriesService.occurrences(ofSeries: try XCTUnwrap(first.seriesParentID), in: fx.context)
        XCTAssertEqual(all.count, SeriesService.horizonWeeks)
        for occurrence in created {
            XCTAssertEqual(occurrence.title, "Schwimmen")
            XCTAssertEqual(occurrence.locationName, "Hallenbad")
            XCTAssertEqual(occurrence.recurrenceRule, "FREQ=WEEKLY")
            XCTAssertEqual(EventService.subjects(of: occurrence).map(\.displayName), ["Mia"])
            XCTAssertEqual(RequiredRoles.decode(occurrence.requiredRolesRaw), [.driveFrom])
            XCTAssertEqual(occurrence.endAt!.timeIntervalSince(occurrence.startAt!), 3600)
            XCTAssertEqual(occurrence.objectID.persistentStore, fx.persistence.privateStore)
        }
        // Offene Zuständigkeiten: pro Termin, in 14 Tagen also zwei.
        XCTAssertEqual(try EventService.openResponsibilities(in: fx.context).count, 2)
    }

    func testBusyOnlySeriesStaysProjected() throws {
        let fx = try Fixture()
        let first = fx.event("Nachtdienst", inHours: 2, visibility: .busyOnly, notes: "Station")
        let created = SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekdays), in: fx.context)
        XCTAssertFalse(created.isEmpty)
        XCTAssertTrue(created.allSatisfy { $0.title == "Belegt" && $0.notes == nil })
    }

    // MARK: Nachlegen

    func testExtendingAddsLaterDatesButNeverRecreatesDeletedOnes() throws {
        let fx = try Fixture()
        let first = fx.event("Chor", inHours: 1)
        let seriesID = try XCTUnwrap({ SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly), in: fx.context); return first.seriesParentID }())
        var all = SeriesService.occurrences(ofSeries: seriesID, in: fx.context)
        let deletedStart = all[3].startAt!
        EventService.softDelete(all[3])
        try fx.save()

        // Heute nichts zu tun: der letzte Termin liegt noch 25 Wochen entfernt.
        XCTAssertEqual(SeriesService.extendAll(household: fx.household, me: fx.owner, in: fx.context), 0)

        let later = Date().addingTimeInterval(10 * 7 * 86_400)
        let added = SeriesService.extendAll(household: fx.household, me: fx.owner, in: fx.context, now: later)
        XCTAssertEqual(added, 10)
        all = SeriesService.occurrences(ofSeries: seriesID, in: fx.context)
        let onDeletedDay = all.filter { $0.startAt == deletedStart }
        XCTAssertEqual(onDeletedDay.count, 1)
        XCTAssertNotNil(onDeletedDay.first?.deletedAt, "Gelöschter Einzeltermin darf nicht zurückkommen")
        XCTAssertEqual(Set(all.compactMap(\.startAt)).count, all.count, "Keine Doppelten")
    }

    func testOnlyTheCreatorExtendsWhileActive() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        let first = fx.event("Chor", inHours: 1)
        SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly), in: fx.context)
        try fx.save()
        let later = Date().addingTimeInterval(10 * 7 * 86_400)

        XCTAssertEqual(SeriesService.extendAll(household: fx.household, me: ben, in: fx.context, now: later), 0)
        let mia = fx.member("Mia", role: .child)
        XCTAssertEqual(SeriesService.extendAll(household: fx.household, me: mia, in: fx.context, now: later), 0,
                       "Kinder legen nichts an")
        fx.owner.isActive = false
        XCTAssertEqual(SeriesService.extendAll(household: fx.household, me: ben, in: fx.context, now: later), 10)
    }

    func testSeriesWithEndStopsAtUntil() throws {
        let fx = try Fixture()
        let first = fx.event("Kurs", inHours: 1)
        let until = Calendar.current.date(byAdding: .day, value: 7 * 4, to: first.startAt!)!
        SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly, until: until), in: fx.context)
        XCTAssertEqual(SeriesService.occurrences(ofSeries: first.seriesParentID!, in: fx.context).count, 5)
        let later = Date().addingTimeInterval(30 * 7 * 86_400)
        XCTAssertEqual(SeriesService.extendAll(household: fx.household, me: fx.owner, in: fx.context, now: later), 0)
    }

    // MARK: Ändern und Beenden

    func testUpdateFollowingShiftsOnlyLaterOccurrencesAndKeepsClaims() throws {
        let fx = try Fixture()
        let first = fx.event("Schwimmen", inHours: 1, roles: [.driveFrom])
        SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly), in: fx.context)
        var all = SeriesService.occurrences(ofSeries: first.seriesParentID!, in: fx.context)
        EventService.claim(role: .driveFrom, on: all[6], by: fx.owner, in: fx.context)
        let pivot = all[5]
        let oldStarts = all.map { $0.startAt! }

        SeriesService.updateFollowing(from: pivot, in: fx.context, title: "Schwimmen neu",
                                      startAt: pivot.startAt!.addingTimeInterval(1800),
                                      endAt: pivot.startAt!.addingTimeInterval(1800 + 5400),
                                      subjects: [fx.owner], requiredRoles: [.driveFrom], kind: .appointment,
                                      visibility: .household, tag: nil, locationName: nil, notes: nil)
        try fx.save()
        all = SeriesService.occurrences(ofSeries: first.seriesParentID!, in: fx.context)
        for (index, occurrence) in all.enumerated() {
            if index < 5 {
                XCTAssertEqual(occurrence.title, "Schwimmen")
                XCTAssertEqual(occurrence.startAt, oldStarts[index])
            } else {
                XCTAssertEqual(occurrence.title, "Schwimmen neu")
                XCTAssertEqual(occurrence.startAt, oldStarts[index].addingTimeInterval(1800))
                XCTAssertEqual(occurrence.endAt!.timeIntervalSince(occurrence.startAt!), 5400)
            }
        }
        XCTAssertTrue(EventService.coveredRoles(of: all[6]).contains(.driveFrom))
    }

    func testEndingSeriesDeletesFollowingAndBlocksExtension() throws {
        let fx = try Fixture()
        let first = fx.event("Chor", inHours: 1)
        SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly), in: fx.context)
        let all = SeriesService.occurrences(ofSeries: first.seriesParentID!, in: fx.context)
        SeriesService.endSeries(before: all[4], keepingEvent: false, in: fx.context)
        try fx.save()

        XCTAssertEqual(all.filter { $0.deletedAt == nil }.count, 4)
        XCTAssertNotNil(Recurrence(encoded: all[3].recurrenceRule)?.until)
        let later = Date().addingTimeInterval(40 * 7 * 86_400)
        XCTAssertEqual(SeriesService.extendAll(household: fx.household, me: fx.owner, in: fx.context, now: later), 0)
    }

    func testChangingRuleStartsNewSeriesFromThisOccurrence() throws {
        let fx = try Fixture()
        let first = fx.event("Chor", inHours: 1)
        SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly), in: fx.context)
        let oldID = first.seriesParentID!
        let pivot = SeriesService.occurrences(ofSeries: oldID, in: fx.context)[2]

        // So speichert der Editor eine geänderte Wiederholung.
        SeriesService.endSeries(before: pivot, keepingEvent: true, in: fx.context)
        SeriesService.detach(pivot)
        SeriesService.startSeries(from: pivot, rule: Recurrence(frequency: .weekly, interval: 2), in: fx.context)
        try fx.save()

        XCTAssertEqual(SeriesService.occurrences(ofSeries: oldID, in: fx.context).filter { $0.deletedAt == nil }.count, 2)
        let new = SeriesService.occurrences(ofSeries: pivot.seriesParentID!, in: fx.context)
        XCTAssertNotEqual(pivot.seriesParentID, oldID)
        XCTAssertEqual(new.first, pivot)
        XCTAssertEqual(new[1].startAt!.timeIntervalSince(pivot.startAt!), 14 * 86_400, accuracy: 3600)
    }

    // MARK: Doppelte und Übernahmen

    func testDuplicatesFromConcurrentExtensionAreMergedWithClaims() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        let first = fx.event("Chor", inHours: 1, roles: [.driveTo])
        SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly), in: fx.context)
        let original = SeriesService.occurrences(ofSeries: first.seriesParentID!, in: fx.context)[3]
        let twin = SeriesService.makeOccurrence(copying: original, startAt: original.startAt!, in: fx.context)
        let (keep, drop) = original.id!.uuidString < twin.id!.uuidString ? (original, twin) : (twin, original)
        EventService.claim(role: .driveTo, on: drop, by: ben, in: fx.context)

        XCTAssertEqual(SeriesService.deduplicate(in: fx.context), 1)
        XCTAssertNil(keep.deletedAt)
        XCTAssertNotNil(drop.deletedAt)
        XCTAssertTrue(EventService.coveredRoles(of: keep).contains(.driveTo), "Übernahme muss mitwandern")
        XCTAssertNoThrow(try fx.save())
    }

    func testClaimFollowingCoversOnlyOpenOccurrences() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        let first = fx.event("Schwimmen", inHours: 1, roles: [.driveFrom])
        SeriesService.startSeries(from: first, rule: Recurrence(frequency: .weekly), in: fx.context)
        let all = SeriesService.occurrences(ofSeries: first.seriesParentID!, in: fx.context)
        EventService.claim(role: .driveFrom, on: all[2], by: ben, in: fx.context)

        let count = SeriesService.claimFollowing(role: .driveFrom, from: all[1], by: fx.owner, in: fx.context)
        XCTAssertEqual(count, all.count - 2, "ab Termin 2, ohne den schon vergebenen")
        XCTAssertTrue(EventService.coveredRoles(of: all[0]).isDisjoint(with: [.driveFrom]), "frühere bleiben offen")
        XCTAssertTrue(try EventService.openResponsibilities(within: 400, in: fx.context).allSatisfy { $0.startAt == all[0].startAt })
    }
}
