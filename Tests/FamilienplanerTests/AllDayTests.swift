import CoreData
import XCTest
@testable import Familienplaner

/// Ganztägige Termine: Urlaub, Ferien, Geburtstage.
@MainActor
final class AllDayTests: XCTestCase {

    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        berlin.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    func testSpanCoversWholeDays() {
        // Ein Tag, Ende als 0 Uhr danach
        var span = EventService.allDaySpan(from: date(2026, 10, 14, 10), to: date(2026, 10, 15), calendar: berlin)
        XCTAssertEqual(span.0, date(2026, 10, 14))
        XCTAssertEqual(span.1, date(2026, 10, 15))
        // EventKit-Ende 23:59:59 am letzten Tag
        span = EventService.allDaySpan(from: date(2026, 10, 14), to: date(2026, 10, 16, 23, 59, 59), calendar: berlin)
        XCTAssertEqual(span.1, date(2026, 10, 17), "drei Tage")
        // Ende gleich Beginn → mindestens ein Tag
        span = EventService.allDaySpan(from: date(2026, 10, 14), to: date(2026, 10, 14), calendar: berlin)
        XCTAssertEqual(span.1, date(2026, 10, 15))
    }

    func testSpanSurvivesDaylightSavingChange() {
        // 25.10.2026 hat 25 Stunden, 29.03.2026 hat 23 Stunden
        var span = EventService.allDaySpan(from: date(2026, 10, 25), to: date(2026, 10, 25).addingTimeInterval(86_400), calendar: berlin)
        XCTAssertEqual(span.1, date(2026, 10, 26))
        span = EventService.allDaySpan(from: date(2026, 3, 29), to: date(2026, 3, 29).addingTimeInterval(86_400), calendar: berlin)
        XCTAssertEqual(span.1, date(2026, 3, 30), "24 h nach 0 Uhr am 23-Stunden-Tag ist 1 Uhr, trotzdem ein Tag")
    }

    func testMakeEventNormalizesAndIsFoundOnEveryDay() throws {
        let fx = try Fixture()
        let calendar = Calendar.current
        let first = calendar.date(byAdding: .day, value: 10, to: calendar.startOfDay(for: Date()))!
        let lastDayNoon = calendar.date(byAdding: .hour, value: 12, to: calendar.date(byAdding: .day, value: 2, to: first)!)!
        let vacation = EventService.makeEvent(in: fx.context, household: fx.household, title: "Urlaub",
                                              startAt: first.addingTimeInterval(3600),
                                              endAt: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDayNoon))!,
                                              createdBy: fx.owner, subjects: [fx.owner], isAllDay: true)
        try fx.save()
        XCTAssertTrue(vacation.isAllDay)
        XCTAssertEqual(vacation.startAt, first)
        XCTAssertEqual(EventService.lastDay(of: vacation), calendar.startOfDay(for: lastDayNoon))
        for offset in 0...2 {
            let day = calendar.date(byAdding: .day, value: offset, to: first)!
            XCTAssertEqual(try fx.count(EventService.eventsRequest(on: day)), 1, "Tag \(offset)")
        }
        XCTAssertEqual(try fx.count(EventService.eventsRequest(on: calendar.date(byAdding: .day, value: 3, to: first)!)), 0)
    }

    func testUpdateKeepsOrSwitchesAllDay() throws {
        let fx = try Fixture()
        let event = fx.event("Ausflug", inHours: 48)
        EventService.update(event, in: fx.context, title: "Ausflug", startAt: event.startAt!, endAt: event.endAt!,
                            subjects: [fx.owner], requiredRoles: [], kind: .appointment, visibility: .household,
                            tag: nil, locationName: nil, notes: nil, isAllDay: true)
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.startAt, Calendar.current.startOfDay(for: event.startAt!))
        XCTAssertEqual(event.endAt!.timeIntervalSince(event.startAt!), 86_400, accuracy: 3600)
    }

    func testYearlyBirthdaySeriesStaysAllDay() throws {
        let fx = try Fixture()
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: Date()))!
        let birthday = EventService.makeEvent(in: fx.context, household: fx.household, title: "Geburtstag",
                                              startAt: day, endAt: calendar.date(byAdding: .day, value: 1, to: day)!,
                                              createdBy: fx.owner, subjects: [fx.owner], isAllDay: true)
        let weekly = SeriesService.startSeries(from: birthday, rule: Recurrence(frequency: .weekly), in: fx.context)
        XCTAssertFalse(weekly.isEmpty)
        for occurrence in weekly {
            XCTAssertTrue(occurrence.isAllDay)
            XCTAssertEqual(occurrence.startAt, calendar.startOfDay(for: occurrence.startAt!))
            XCTAssertEqual(calendar.dateComponents([.day], from: occurrence.startAt!, to: occurrence.endAt!).day, 1,
                           "über die Zeitumstellung genau ein Tag")
        }
    }

    func testExportMarksAllDay() throws {
        let fx = try Fixture()
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400 * 5))
        let event = EventService.makeEvent(in: fx.context, household: fx.household, title: "Schulfrei",
                                           startAt: day, endAt: day.addingTimeInterval(86_400),
                                           createdBy: fx.owner, subjects: [fx.owner], isAllDay: true)
        let content = CalendarExportService.content(for: event, me: fx.owner, household: fx.household)
        XCTAssertTrue(content.isAllDay)
        XCTAssertEqual(content.start, day)
    }
}
