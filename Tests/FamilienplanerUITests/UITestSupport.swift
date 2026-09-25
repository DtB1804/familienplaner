import XCTest

/// Gemeinsame Schritte der Oberflächentests. Die App startet mit `-uiTesting`:
/// Daten nur im Arbeitsspeicher, kein iCloud, jeder Start beginnt leer.
extension XCTestCase {

    @MainActor
    func launchFreshApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        return app
    }

    @MainActor
    func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    func tap(_ id: String, in app: XCUIApplication, timeout: TimeInterval = 5,
             file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(id) fehlt", file: file, line: line)
        target.tap()
    }

    @MainActor
    func type(_ text: String, into id: String, in app: XCUIApplication) {
        let field = element(id, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(id) fehlt")
        field.tap()
        field.typeText(text)
    }

    /// Schalter in Formularen: Tippen auf den rechten Rand trifft den Switch sicher.
    @MainActor
    func setSwitch(_ id: String, on: Bool, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = app.switches[id].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "\(id) fehlt", file: file, line: line)
        var tries = 0
        while !toggle.isHittable && tries < 6 { app.swipeUp(velocity: .slow); tries += 1 }
        if (toggle.value as? String == "1") != on {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "\(id) nicht umgeschaltet", file: file, line: line)
    }

    /// Einrichten: Haushalt mit Anna als erster Erwachsener.
    @MainActor
    func completeSetup(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Einrichten"].waitForExistence(timeout: 15), "Einrichten erscheint nicht")
        type("Testfamilie", into: "setup.household", in: app)
        type("Anna", into: "setup.name", in: app)
        tap("setup.create", in: app)
        XCTAssertTrue(element("toolbar.family", in: app).waitForExistence(timeout: 10), "Tagesansicht erscheint nicht")
    }

    /// Mitglied ohne eigenes iPhone anlegen (Rolle Kind ist voreingestellt).
    @MainActor
    func addChild(_ name: String, in app: XCUIApplication) {
        tap("toolbar.family", in: app)
        tap("members.add", in: app)
        type(name, into: "member.name", in: app)
        tap("member.save", in: app)
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5), "\(name) fehlt in der Liste")
    }

    /// Neuer Termin am aktuell gezeigten Tag, im Testmodus immer 10:00–10:30.
    @MainActor
    func createEvent(_ title: String, subjects: [String] = [], deselectMe: Bool = false,
                     roles: [String] = [], in app: XCUIApplication) {
        tap("toolbar.new", in: app)
        type(title, into: "editor.title", in: app)
        if deselectMe { tap("editor.subject.Anna", in: app) }
        for name in subjects { tap("editor.subject.\(name)", in: app) }
        for role in roles { setSwitch("editor.role.\(role)", on: true, in: app) }
        tap("editor.save", in: app)
        XCTAssertTrue(element("event.\(title)", in: app).waitForExistence(timeout: 5), "\(title) nicht im Kalender")
    }
}
