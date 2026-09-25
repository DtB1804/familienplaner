import CoreData
import XCTest
@testable import Familienplaner

/// Lasttest: ein Familienjahr mit rund 1.500 Terminen.
@MainActor
final class PerformanceTests: XCTestCase {

    func testWeekQueryAndOpenResponsibilitiesWithAYearOfEvents() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        for i in 0..<1500 {
            fx.event("Termin \(i)", inHours: Double(i) * 5.8, length: 1,
                     subjects: [i % 2 == 0 ? fx.owner : mia],
                     roles: i % 3 == 0 ? [.driveTo] : [])
        }
        try fx.save()

        let start = TodayScreen.weekStart(of: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        measure(metrics: [XCTClockMetric()]) {
            fx.context.refreshAllObjects()
            _ = try? fx.context.fetch(EventService.eventsRequest(from: start, to: end))
            _ = try? EventService.openResponsibilities(in: fx.context)
            _ = try? fx.context.fetch(EventService.searchRequest("Termin 14"))
        }
    }
}
