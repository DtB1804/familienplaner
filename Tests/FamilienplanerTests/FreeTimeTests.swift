import CoreData
import XCTest
@testable import Familienplaner

/// Freiraum-Finder: wann haben alle ausgewählten Personen gleichzeitig frei?
@MainActor
final class FreeTimeTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }

    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    private typealias I = FreeTimeFinder.Interval

    func testGapsBetweenMergedBusyBlocks() {
        // Mi 14.10.: belegt 9–10, 9:30–11 (überlappend), 15–16
        let busy = [I(start: at(14, 9), end: at(14, 10)), I(start: at(14, 9, 30), end: at(14, 11)),
                    I(start: at(14, 15), end: at(14, 16))]
        let slots = FreeTimeFinder.freeSlots(busy: busy, now: at(14, 6), days: 1, dayPart: .wholeDay,
                                             filter: .all, minimum: 3600, calendar: calendar)
        XCTAssertEqual(slots, [I(start: at(14, 7), end: at(14, 9)),
                               I(start: at(14, 11), end: at(14, 15)),
                               I(start: at(14, 16), end: at(14, 22))])
    }

    func testMinimumDurationFiltersShortGaps() {
        let busy = [I(start: at(14, 7, 30), end: at(14, 12))]
        let slots = FreeTimeFinder.freeSlots(busy: busy, now: at(14, 6), days: 1, dayPart: .morning,
                                             filter: .all, minimum: 3600, calendar: calendar)
        XCTAssertTrue(slots.isEmpty, "7:00–7:30 ist kürzer als eine Stunde")
    }

    func testStartsNotBeforeNowRoundedToQuarterHour() {
        let slots = FreeTimeFinder.freeSlots(busy: [], now: at(14, 13, 7), days: 1, dayPart: .afternoon,
                                             filter: .all, minimum: 1800, calendar: calendar)
        XCTAssertEqual(slots.first?.start, at(14, 13, 15))
        XCTAssertEqual(slots.first?.end, at(14, 18))
    }

    func testWeekendAndWeekdayFilter() {
        // 14.10.2026 ist ein Mittwoch; Sa 17., So 18.
        let weekend = FreeTimeFinder.freeSlots(busy: [], now: at(14, 6), days: 7, dayPart: .wholeDay,
                                               filter: .weekend, minimum: 3600, calendar: calendar)
        XCTAssertEqual(weekend.map { calendar.component(.day, from: $0.start) }, [17, 18])
        let weekdays = FreeTimeFinder.freeSlots(busy: [], now: at(14, 6), days: 7, dayPart: .wholeDay,
                                                filter: .weekdays, minimum: 3600, calendar: calendar)
        XCTAssertEqual(weekdays.count, 5)
    }

    func testBusyComesFromSubjectsAndDutiesOfSelectedMembers() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        let ben = fx.member("Ben")
        let miaSwim = fx.event("Schwimmen", inHours: 24, subjects: [mia], roles: [.driveFrom])
        fx.event("Ben allein", inHours: 30, subjects: [ben])
        let annaDrives = fx.event("Fußball", inHours: 50, subjects: [mia], roles: [.driveTo])
        EventService.claim(role: .driveTo, on: annaDrives, by: fx.owner, in: fx.context)
        let declined = fx.event("Abgesagt", inHours: 70, subjects: [mia], roles: [.accompany])
        EventService.addParticipation(in: fx.context, event: declined, member: fx.owner, role: .accompany, status: .declined)
        let deleted = fx.event("Gelöscht", inHours: 80)
        EventService.softDelete(deleted)
        let vacationDay = Calendar.current.startOfDay(for: Date().addingTimeInterval(5 * 86_400))
        EventService.makeEvent(in: fx.context, household: fx.household, title: "Urlaub", startAt: vacationDay,
                               endAt: vacationDay.addingTimeInterval(86_400), createdBy: fx.owner,
                               subjects: [fx.owner], isAllDay: true)
        EventService.makeEvent(in: fx.context, household: fx.household, title: "Dienst", startAt: vacationDay.addingTimeInterval(86_400),
                               endAt: vacationDay.addingTimeInterval(2 * 86_400), createdBy: fx.owner,
                               subjects: [fx.owner], kind: .statusBlock, visibility: .busyOnly, isAllDay: true)
        let all = try fx.context.fetch(NSFetchRequest<CDEvent>(entityName: "CDEvent"))

        let annaBusy = FreeTimeFinder.busyIntervals(events: all, members: [fx.owner])
        XCTAssertEqual(annaBusy.map(\.start), [annaDrives.startAt!, vacationDay.addingTimeInterval(86_400)],
                       "Nur übernommene Fahrt und ganztägiger Dienst; kein Urlaub, nichts Abgesagtes oder Gelöschtes")

        let miaBusy = FreeTimeFinder.busyIntervals(events: all, members: [mia])
        XCTAssertEqual(miaBusy.first?.start, miaSwim.startAt)
        XCTAssertEqual(miaBusy.count, 3)

        let both = FreeTimeFinder.busyIntervals(events: all, members: [fx.owner, ben])
        XCTAssertEqual(both.count, 3)
    }

    func testMergeJoinsTouchingIntervals() {
        let merged = FreeTimeFinder.merge([I(start: at(14, 10), end: at(14, 11)), I(start: at(14, 11), end: at(14, 12))])
        XCTAssertEqual(merged, [I(start: at(14, 10), end: at(14, 12))])
    }
}
