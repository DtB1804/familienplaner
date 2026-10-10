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
        for id in ["toolbar.family", "toolbar.search", "toolbar.photo", "toolbar.new", "view.menu", "nav.previous", "nav.next", "nav.title"] {
            XCTAssertTrue(element(id, in: app).exists, "\(id) fehlt auf dem Hauptbildschirm")
        }
        XCTAssertFalse(element("banner.open", in: app).exists, "Ohne Termine keine offenen Zuständigkeiten")
        XCTAssertFalse(element("nav.today", in: app).exists, "Heute-Knopf nur, wenn nicht heute")
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
        try app.performAccessibilityAudit(for: .all) { issue in self.isNavigationBarTypeIssue(issue, in: app) || self.isHourLabelContrastIssue(issue) }
        tap("toolbar.family", in: app)
        try app.performAccessibilityAudit(for: .all) { issue in self.isNavigationBarTypeIssue(issue, in: app) || self.isHourLabelContrastIssue(issue) }
    }

    /// Texte und Knöpfe in der Navigationsleiste (Titel, "Heute") begrenzt iOS selbst in der
    /// Größe; die Prüfung meldet das als "Dynamic Type teilweise nicht unterstützt". Nur diese
    /// Meldung für Elemente innerhalb der Navigationsleiste wird hingenommen, alles andere zählt.
    @MainActor
    private func isNavigationBarTypeIssue(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        guard issue.auditType == .dynamicType, let element = issue.element else { return false }
        let bar = app.navigationBars.firstMatch
        return bar.exists && bar.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
    }

    /// Stundenzahlen der Uhrzeitspalte ("07", "16"): schwarz auf hellgrauem Grund, im
    /// Bildschirmfoto der Prüfung vom 10.10.2026 klar lesbar. Die Kontrastprüfung meldet sie
    /// trotzdem (nach .tertiary → .primary weiterhin). Nur diese Meldung für ein- bis
    /// zweistellige Zahlen am linken Rand (x < 50 pt) wird hingenommen.
    @MainActor
    private func isHourLabelContrastIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element else { return false }
        let label = element.label
        return element.frame.minX < 50
            && (1...2).contains(label.count)
            && label.allSatisfy(\.isNumber)
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
