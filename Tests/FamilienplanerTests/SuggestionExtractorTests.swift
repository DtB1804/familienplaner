import XCTest
@testable import Familienplaner

/// Termine aus Fotos: Regeln für Beginn/Ende, Sprache, Datumserkennung ohne KI.
@MainActor
final class SuggestionExtractorTests: XCTestCase {

    private let calendar = Calendar.current
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))! }
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testMissingTimeDefaultsToEightAndIsMarkedAsGuess() {
        let s = SuggestionExtractor.makeSuggestion(title: "Wandertag", day: day, start: nil, end: nil, location: nil)
        XCTAssertEqual(s.start, at(8))
        XCTAssertEqual(s.end, at(8, 30))
        XCTAssertTrue(s.timeIsGuessed)
    }

    func testEndIsAtLeastThirtyMinutesAfterStart() {
        let before = SuggestionExtractor.makeSuggestion(title: "A", day: day, start: at(10), end: at(9), location: nil)
        XCTAssertEqual(before.end, at(10, 30))
        let short = SuggestionExtractor.makeSuggestion(title: "A", day: day, start: at(10), end: at(10, 10), location: nil)
        XCTAssertEqual(short.end, at(10, 30))
        let valid = SuggestionExtractor.makeSuggestion(title: "A", day: day, start: at(10), end: at(11, 15), location: nil)
        XCTAssertEqual(valid.end, at(11, 15))
        XCTAssertFalse(valid.timeIsGuessed)
    }

    func testImplausiblyLongEventIsShortened() {
        // Früherer Fehler: 00:00–23:59 aus dem Foto
        let s = SuggestionExtractor.makeSuggestion(title: "A", day: day, start: at(0), end: at(23, 59), location: nil)
        XCTAssertEqual(s.end, at(0, 30))
    }

    func testTitleFallbackAndLimit() {
        XCTAssertEqual(SuggestionExtractor.makeSuggestion(title: "", day: day, start: nil, end: nil, location: nil).title, "Termin")
        let long = String(repeating: "x", count: 100)
        XCTAssertEqual(SuggestionExtractor.makeSuggestion(title: long, day: day, start: nil, end: nil, location: nil).title.count, 60)
    }

    func testLanguageDetection() {
        XCTAssertTrue(SuggestionExtractor.isClearlyEnglish(
            "Swimming practice for the whole team takes place at the public pool every Monday afternoon."))
        XCTAssertFalse(SuggestionExtractor.isClearlyEnglish(
            "Das Schwimmtraining für die ganze Mannschaft findet jeden Montagnachmittag im Hallenbad statt."))
    }

    func testDateDetectorFindsFutureDateAndIgnoresPast() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        let text = """
        Parent evening October 14, 2026 at 7:30 PM
        Parent evening October 14, 2026 at 7:30 PM
        Old meeting January 5, 2020 at 10:00 AM
        """
        let found = SuggestionExtractor.extractWithDetector(text: text, now: now)
        XCTAssertEqual(found.count, 1, "Doppelte Zeile zusammengeführt, Vergangenheit ignoriert: \(found)")
        guard let first = found.first else { return }
        XCTAssertEqual(calendar.component(.hour, from: first.start), 19)
        XCTAssertEqual(calendar.component(.minute, from: first.start), 30)
        XCTAssertEqual(first.end.timeIntervalSince(first.start), 30 * 60)
        XCTAssertTrue(first.title.contains("Parent evening"), first.title)
        XCTAssertFalse(first.timeIsGuessed)
    }
}
