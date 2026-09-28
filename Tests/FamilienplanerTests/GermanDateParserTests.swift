import XCTest
@testable import Familienplaner

/// Deutsche Datums- und Zeitangaben ohne KI (Elternbriefe, WhatsApp-Nachrichten).
@MainActor
final class GermanDateParserTests: XCTestCase {

    private let calendar = Calendar.current
    /// Donnerstag, 1. Oktober 2026, 9 Uhr
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))! }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testNumericDateWithTime() {
        let r = GermanDateParser.parse(line: "Elternabend am 14.10. um 19:30 Uhr", now: now)
        XCTAssertEqual(r.found.count, 1)
        XCTAssertEqual(r.found.first?.day, day(2026, 10, 14))
        XCTAssertEqual(r.found.first?.start?.hour, 19)
        XCTAssertEqual(r.found.first?.start?.minute, 30)
        XCTAssertEqual(r.rest, "Elternabend")
    }

    func testNamedMonthAndUhrTime() {
        let r = GermanDateParser.parse(line: "Laternenumzug 7. November 18 Uhr", now: now)
        XCTAssertEqual(r.found.first?.day, day(2026, 11, 7))
        XCTAssertEqual(r.found.first?.start?.hour, 18)
        XCTAssertEqual(r.rest, "Laternenumzug")
    }

    func testTimeRangeWithDots() {
        let r = GermanDateParser.parse(line: "Sportfest 16.10.2026, 8.30-12.00 Uhr", now: now)
        XCTAssertEqual(r.found.first?.day, day(2026, 10, 16))
        XCTAssertEqual(r.found.first?.start?.hour, 8)
        XCTAssertEqual(r.found.first?.start?.minute, 30)
        XCTAssertEqual(r.found.first?.end?.hour, 12)
        XCTAssertEqual(r.rest, "Sportfest")
    }

    func testDateRangeIsAllDay() {
        let r = GermanDateParser.parse(line: "Klassenfahrt vom 12. bis 14.10.", now: now)
        XCTAssertEqual(r.found.count, 1)
        XCTAssertEqual(r.found.first?.day, day(2026, 10, 12))
        XCTAssertEqual(r.found.first?.lastDay, day(2026, 10, 14))
        XCTAssertNil(r.found.first?.start)
        XCTAssertEqual(r.rest, "Klassenfahrt")

        let named = GermanDateParser.parse(line: "Herbstferien 19.–30. Oktober", now: now)
        XCTAssertEqual(named.found.first?.lastDay, day(2026, 10, 30))
    }

    func testWeekdayWithTimeMeansNextOccurrence() {
        let r = GermanDateParser.parse(line: "Training Dienstag 17:00", now: now)
        XCTAssertEqual(r.found.count, 1)
        guard let found = r.found.first?.day else { return }
        XCTAssertEqual(calendar.component(.weekday, from: found), 3, "Dienstag")
        XCTAssertGreaterThanOrEqual(found, calendar.startOfDay(for: now))
        XCTAssertLessThan(found, calendar.date(byAdding: .day, value: 7, to: now)!)
        XCTAssertEqual(r.rest, "Training")
    }

    func testWeekdayWithoutTimeIsIgnored() {
        XCTAssertTrue(GermanDateParser.parse(line: "Montags gibt es Nudeln", now: now).found.isEmpty)
    }

    func testPastDateWithoutYearMovesToNextYear() {
        let r = GermanDateParser.parse(line: "Sommerfest 20.6.", now: now)
        XCTAssertEqual(r.found.first?.day, day(2027, 6, 20))
    }

    func testInvalidMonthIsNoDate() {
        // "19.30." am Satzende ist eine Uhrzeit, kein Datum
        let r = GermanDateParser.parse(line: "Treffen 3.10. ab 19.30 Uhr.", now: now)
        XCTAssertEqual(r.found.count, 1)
        XCTAssertEqual(r.found.first?.day, day(2026, 10, 3))
        XCTAssertEqual(r.found.first?.start?.hour, 19)
        XCTAssertEqual(r.found.first?.start?.minute, 30)
    }

    func testNumbersWithoutUhrAreNoTime() {
        let r = GermanDateParser.parse(line: "Klasse 3-4 Ausflug 9.10.", now: now)
        XCTAssertNil(r.found.first?.start)
    }

    // MARK: - Zusammenspiel im Extractor

    func testPreviousLineBecomesTitle() {
        let text = """
        Elternabend Klasse 4b
        Dienstag, 14.10.2026, 19:30 Uhr
        Aula
        """
        let found = SuggestionExtractor.extractWithDetector(text: text, now: now)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.title, "Elternabend Klasse 4b")
        XCTAssertEqual(found.first.map { calendar.component(.hour, from: $0.start) }, 19)
        XCTAssertEqual(found.first?.timeIsGuessed, false)
    }

    func testRangeBecomesAllDaySuggestion() {
        let found = SuggestionExtractor.extractWithDetector(text: "Klassenfahrt 12.–14.10.", now: now)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.isAllDay, true)
        XCTAssertEqual(found.first?.start, day(2026, 10, 12))
        XCTAssertEqual(found.first?.end, day(2026, 10, 15), "Ende exklusiv, 0 Uhr nach dem letzten Tag")
    }

    func testWhatsAppMessage() {
        let found = SuggestionExtractor.extractWithDetector(
            text: "Hallo zusammen, Elternabend ist am 21.10. von 19:00 bis 20:30 im Musikraum. LG", now: now)
        XCTAssertEqual(found.count, 1)
        guard let s = found.first else { return }
        XCTAssertEqual(calendar.component(.hour, from: s.start), 19)
        XCTAssertEqual(calendar.component(.hour, from: s.end), 20)
        XCTAssertEqual(calendar.component(.minute, from: s.end), 30)
        XCTAssertTrue(s.title.contains("Elternabend"), s.title)
    }

    func testOldSuggestionsWithoutAllDayStillDecode() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"A","start":0,"end":1800,"timeIsGuessed":false}]"#
        let decoded = try JSONDecoder().decode([SuggestedEvent].self, from: Data(json.utf8))
        XCTAssertNil(decoded.first?.isAllDay)
    }
}
