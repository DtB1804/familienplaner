import XCTest

/// Smoke-Test: Startet die App, lässt sich ein Haushalt anlegen, erscheint der Kalender?
final class SmokeTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testLaunchSetupAndMainScreen() {
        let app = launchFreshApp()
        XCTAssertTrue(app.navigationBars["Einrichten"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["setup.create"].isEnabled, "Anlegen ohne Eingaben muss gesperrt sein")

        completeSetup(in: app)
        for id in ["toolbar.family", "toolbar.search", "toolbar.new", "mode", "nav.previous", "nav.next"] {
            XCTAssertTrue(element(id, in: app).exists, "\(id) fehlt auf dem Hauptbildschirm")
        }
        XCTAssertFalse(element("banner.open", in: app).exists, "Ohne Termine keine offenen Zuständigkeiten")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Barrierefreiheit: automatische Prüfung von Apple (Kontrast, Beschriftungen,
    /// Trefferflächen, abgeschnittener Text, große Schrift) auf Hauptbildschirm und Familie.
    @MainActor
    func testAccessibilityAudit() throws {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("nav.next", in: app)
        createEvent("Schwimmen", roles: ["driveFrom"], in: app)
        try app.performAccessibilityAudit()
        tap("toolbar.family", in: app)
        try app.performAccessibilityAudit()
    }

    /// Erste Schritte nach dem Einrichten (im Test nur mit -showOnboarding sichtbar).
    @MainActor
    func testOnboardingAppearsOnceAndCanBeClosed() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-showOnboarding", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        completeSetup(in: app)
        XCTAssertTrue(app.navigationBars["Erste Schritte"].waitForExistence(timeout: 5), "Erste Schritte fehlen")
        XCTAssertTrue(element("onboarding.calendars", in: app).exists)
        XCTAssertTrue(app.switches["onboarding.remindEvents"].exists)
        tap("onboarding.done", in: app)
        XCTAssertTrue(app.navigationBars["Erste Schritte"].waitForNonExistence(timeout: 5))
    }
}
