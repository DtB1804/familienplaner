import CoreData
import XCTest
@testable import Familienplaner

/// Zeitstrahl-Bereich: normal 6–23 Uhr, frühe und späte Termine erweitern ihn.
@MainActor
final class TimelineHoursTests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 1) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func event(_ f: Fixture, from start: Date, to end: Date) -> CDEvent {
        EventService.makeEvent(in: f.context, household: f.household, title: "X",
                               startAt: start, endAt: end, createdBy: f.owner,
                               subjects: [f.owner], requiredRoles: [])
    }

    func testDefaultRange() throws {
        let f = try Fixture()
        let e = event(f, from: at(10), to: at(11))
        XCTAssertEqual(TimelineHours.range(for: [e]), 6...23)
        XCTAssertEqual(TimelineHours.range(for: []), 6...23)
    }

    func testEarlyAndLateEventsExtendRange() throws {
        let f = try Fixture()
        let early = event(f, from: at(5, 30), to: at(7))
        let late = event(f, from: at(22), to: at(23, 30))
        XCTAssertEqual(TimelineHours.range(for: [early, late]), 5...24)
    }

    func testOvernightEventReachesMidnight() throws {
        let f = try Fixture()
        let night = event(f, from: at(21), to: at(6, dayOffset: 2))
        XCTAssertEqual(TimelineHours.range(for: [night]).upperBound, 24)
    }
}
