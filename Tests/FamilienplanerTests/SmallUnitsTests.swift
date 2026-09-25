import EventKit
import XCTest
@testable import Familienplaner

@MainActor
final class SmallUnitsTests: XCTestCase {

    // MARK: Zoom

    func testZoomLevelsAreOrderedAndBounded() {
        let all = DayZoom.allCases
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all.map(\.pointsPerHour), all.map(\.pointsPerHour).sorted())
        XCTAssertEqual(all.map(\.minimumLabelDuration), all.map(\.minimumLabelDuration).sorted(by: >))
        XCTAssertFalse(DayZoom.overview.canZoomOut)
        XCTAssertFalse(DayZoom.large.canZoomIn)
        XCTAssertEqual(DayZoom.large.zoomedIn(), .large)
        XCTAssertEqual(DayZoom.overview.zoomedOut(), .overview)
        XCTAssertEqual(DayZoom.normal.zoomedIn(), .detailed)
    }

    // MARK: Wochenbeginn

    func testWeekStartsOnMonday() {
        let calendar = Calendar.current
        func date(_ d: Int, _ h: Int = 15) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))!
        }
        let monday = calendar.startOfDay(for: date(21))
        XCTAssertEqual(TodayScreen.weekStart(of: date(23)), monday)      // Mittwoch
        XCTAssertEqual(TodayScreen.weekStart(of: date(27, 23)), monday)  // Sonntag spät
        XCTAssertEqual(TodayScreen.weekStart(of: date(21, 0)), monday)   // Montag 0 Uhr
        XCTAssertEqual(TodayScreen.weekStart(of: date(28, 0)), calendar.startOfDay(for: date(28)))
    }

    // MARK: Watch-Ausschnitt

    func testWatchSnapshotRoundTrip() throws {
        let snapshot = WatchSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000), viewerName: "Anna", canClaim: true,
            events: [.init(id: "1", title: "Schwimmen", start: Date(timeIntervalSince1970: 1_790_003_600),
                           end: Date(timeIntervalSince1970: 1_790_007_200), location: nil, people: "AN, MI",
                           rgb: 0x33AA55, openRoles: ["Holt"], busy: false)],
            open: [.init(eventID: "1", role: "driveFrom", roleLabel: "Holt", title: "Schwimmen",
                         start: Date(timeIntervalSince1970: 1_790_003_600))])
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WatchSnapshot.self, from: data), snapshot)
        XCTAssertEqual(snapshot.open.first?.id, "1-driveFrom")
    }

    // MARK: Erinnerungen

    func testReminderSettingsFallBackToSafeDefaults() {
        let defaults = UserDefaults.standard
        let keys = [ReminderSettings.leadMinutesKey, ReminderSettings.openHourKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }

        keys.forEach { defaults.removeObject(forKey: $0) }
        XCTAssertEqual(ReminderSettings.leadMinutes, 15)
        XCTAssertEqual(ReminderSettings.openHour, 19)
        defaults.set(30, forKey: ReminderSettings.openHourKey)
        XCTAssertEqual(ReminderSettings.openHour, 19)
        defaults.set(60, forKey: ReminderSettings.leadMinutesKey)
        XCTAssertEqual(ReminderSettings.leadMinutes, 60)
        XCTAssertTrue(ReminderSettings.leadChoices.contains(ReminderSettings.leadMinutes))
    }

    // MARK: Kalenderübernahme (Regel 14)

    func testOccurrenceKeyCombinesIdentifierAndOccurrence() {
        let event = EKEvent(eventStore: EKEventStore())
        event.startDate = Date(timeIntervalSince1970: 1_790_000_000)
        event.endDate = event.startDate.addingTimeInterval(3600)
        let key = CalendarImportService.occurrenceKey(event)
        XCTAssertTrue(key.hasSuffix("|1790000000"), key)
        XCTAssertFalse(key.hasPrefix("|"), "Kennung darf nicht leer sein: \(key)")
    }
}
