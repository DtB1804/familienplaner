import CoreData
import XCTest
@testable import Familienplaner

/// Kinderansicht (Anzeige-Schalter, CLAUDE.md Regel 2, Ausnahme vom 22.09.2026).
@MainActor
final class PresentationTests: XCTestCase {

    func testChildSeesBusyForAdultEventsWhenSwitchIsOff() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        fx.household.childrenSeeAdultTitles = false
        let adultEvent = fx.event("Zahnarzt", location: "Praxis")
        XCTAssertEqual(EventPresentation.title(of: adultEvent, for: mia, in: fx.household), "Belegt")
        XCTAssertNil(EventPresentation.location(of: adultEvent, for: mia, in: fx.household))
        XCTAssertTrue(EventPresentation.isBusyOnly(adultEvent, for: mia, in: fx.household))
    }

    func testEventsConcerningAChildStayReadableForChildren() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        let tom = fx.member("Tom", role: .child)
        fx.household.childrenSeeAdultTitles = false
        let tomsEvent = fx.event("Turnen", subjects: [tom, fx.owner])
        XCTAssertEqual(EventPresentation.title(of: tomsEvent, for: mia, in: fx.household), "Turnen",
                       "Kinder sehen die Termine des anderen Kindes")
    }

    func testChildSeesTitlesWhenSwitchIsOn() throws {
        let fx = try Fixture()
        let mia = fx.member("Mia", role: .child)
        fx.household.childrenSeeAdultTitles = true
        let event = fx.event("Zahnarzt")
        XCTAssertEqual(EventPresentation.title(of: event, for: mia, in: fx.household), "Zahnarzt")
    }

    func testAdultsAlwaysSeeTitlesButBusyOnlyStaysBusy() throws {
        let fx = try Fixture()
        let ben = fx.member("Ben")
        fx.household.childrenSeeAdultTitles = false
        let event = fx.event("Zahnarzt")
        let shift = fx.event("Frühdienst", visibility: .busyOnly)
        XCTAssertEqual(EventPresentation.title(of: event, for: ben, in: fx.household), "Zahnarzt")
        XCTAssertFalse(EventPresentation.isBusyOnly(event, for: ben, in: fx.household))
        XCTAssertEqual(EventPresentation.title(of: shift, for: ben, in: fx.household), "Belegt")
        XCTAssertTrue(EventPresentation.isBusyOnly(shift, for: ben, in: fx.household))
    }
}
