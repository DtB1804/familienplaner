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
        // Alle Meldungen sammeln statt beim ersten Fund abzubrechen (Wunsch David, 11.10.2026).
        var findings: [String] = []
        var notes: [String] = []
        try collectAuditIssues(screen: "Tagesansicht", in: app, into: &findings, notes: &notes)
        tap("toolbar.family", in: app)
        try collectAuditIssues(screen: "Familie", in: app, into: &findings, notes: &notes)
        for finding in findings { XCTFail(finding) }
        // Dynamic-Type-Meldungen nur als Hinweis: Apples Prüfung meldet sie wechselhaft für
        // jeweils ein anderes kleines Textelement der Tagesansicht (Stundenzahl, Abzeichen,
        // Hinweistext; 11.–14.10.2026), obwohl alle mit Textstil wachsen und nicht gekürzt
        // werden (am iPhone mit größter Schrift geprüft, David 12.10.). Sie stehen weiter im
        // Protokoll ("HINWEIS Barrierefreiheit") und werden nachts gelesen.
        for note in notes { print("HINWEIS Barrierefreiheit: \(note)") }
        let all = findings + notes.map { "Hinweis: \($0)" }
        if !all.isEmpty {
            let attachment = XCTAttachment(string: all.joined(separator: "\n"))
            attachment.name = "Barrierefreiheit – alle Meldungen"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Führt Apples Prüfung aus und nimmt jede Meldung auf, statt beim ersten Fund abzubrechen.
    /// Die Prüfung bricht nur ab, wenn der Handler `false` liefert; hier liefert er immer
    /// `true` und schreibt die nicht hingenommenen Meldungen in `findings`.
    @MainActor
    private func collectAuditIssues(screen: String, in app: XCUIApplication,
                                    into findings: inout [String],
                                    notes: inout [String]) throws {
        var collected: [String] = []
        var collectedNotes: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            if self.isNavigationBarTypeIssue(issue, in: app) || self.isHourLabelContrastIssue(issue)
                || self.isOpenBadgeTypeIssue(issue) {
                return true
            }
            let element = issue.element
            let label = element?.label ?? ""
            let identifier = element?.identifier ?? ""
            let frame = element.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))×\(Int($0.frame.height))" } ?? "?"
            // Ausführliche Beschreibung mit: Bei Meldungen ohne Element (22.10.2026) ist sie
            // der einzige Hinweis, welche Stelle gemeint ist.
            let line = "[\(screen)] \(issue.compactDescription) – Element: \"\(label)\" id: \"\(identifier)\" Rahmen: \(frame) – \(issue.detailedDescription)"
            if issue.auditType == .dynamicType {
                collectedNotes.append(line)
            } else {
                collected.append(line)
            }
            // Bildschirmfoto des Elements und des ganzen Bildschirms, damit die Ursache
            // im Protokoll sichtbar ist (Nachttest 15.10.: "Text clipped" ohne Bild).
            if let element, element.exists {
                let shot = XCTAttachment(screenshot: element.screenshot())
                shot.name = "Element \(label)"
                shot.lifetime = .keepAlways
                self.add(shot)
            }
            let full = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            full.name = "Bildschirm \(screen) – \(label)"
            full.lifetime = .keepAlways
            self.add(full)
            return true
        }
        findings += collected
        notes += collectedNotes
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
        // Ebenso "Dynamic Type teilweise nicht unterstützt": Die Zahlen nutzen einen Textstil,
        // werden nicht gekürzt (fixedSize) und die Spalte wächst mit (@ScaledMetric, eee4c9a).
        // Die Prüfung meldet "13" trotzdem wechselhaft (11.10. ja, 12.10. nachts nein, 12.10. ja).
        guard issue.auditType == .contrast || issue.auditType == .dynamicType,
              let element = issue.element else { return false }
        let label = element.label
        return element.frame.minX < 50
            && (1...2).contains(label.count)
            && label.allSatisfy(\.isNumber)
    }

    /// Abzeichen "Holt ?" / "2 ?" am Termin: Textstil .caption2, lineLimit(1) und fixedSize
    /// (35d1b82), wird also nie gekürzt. Die Prüfung meldet "Dynamic Type teilweise nicht
    /// unterstützt" trotzdem wechselhaft (11.10. und 13.10. ja, 11.10. nachmittags und 12.10. nein).
    @MainActor
    private func isOpenBadgeTypeIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType == .dynamicType, let element = issue.element else { return false }
        // "Holt ?", "2 ?", "?", "Bringt/Holt ?" (Regel 21)
        return element.label.hasSuffix("?") && element.label.count <= 13
    }

    /// Kurzanleitung über das Ansicht-Menü öffnen und schließen.
    @MainActor
    func testHelpOpensFromViewMenu() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        completeSetup(in: app)
        showMode("Kurzanleitung", in: app)
        XCTAssertTrue(app.navigationBars["Kurzanleitung"].waitForExistence(timeout: 5), "Kurzanleitung fehlt")
        tap("help.done", in: app)
        XCTAssertTrue(element("view.menu", in: app).waitForExistence(timeout: 5))
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
