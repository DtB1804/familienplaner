import XCTest

/// Smoke-Test: Startet die App, lässt sich ein Haushalt anlegen, erscheint der Kalender?
final class SmokeTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testLaunchSetupAndMainScreen() {
        let app = launchFreshApp()
        XCTAssertTrue(app.navigationBars["Einrichten"].waitForExistence(timeout: 15))
        XCTAssertFalse(element("setup.create", in: app).isEnabled, "Anlegen ohne Eingaben muss gesperrt sein")

        completeSetup(in: app)
        for id in ["toolbar.family", "toolbar.search", "toolbar.new", "mode", "nav.previous", "nav.next"] {
            XCTAssertTrue(element(id, in: app).exists, "\(id) fehlt auf dem Hauptbildschirm")
        }
        XCTAssertFalse(element("banner.open", in: app).exists, "Ohne Termine keine offenen Zuständigkeiten")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
