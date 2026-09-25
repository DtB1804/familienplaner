import XCTest

/// End-to-End-Abläufe aus Sicht der Familie, jeweils auf frisch gestarteter App.
final class EndToEndTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Termin mit "Holt nötig" → Hinweis → übernehmen → suchen → Woche → löschen.
    @MainActor
    func testAppointmentLifecycleWithResponsibility() {
        let app = launchFreshApp()
        completeSetup(in: app)
        addChild("Mia", in: app)
        tap("members.done", in: app)

        // Morgen, damit 10:00 sicher in der Zukunft liegt (offene Zuständigkeiten ab jetzt).
        tap("nav.next", in: app)
        createEvent("Schwimmen", subjects: ["Mia"], roles: ["driveFrom"], in: app)
        XCTAssertEqual(element("event.Schwimmen", in: app).value as? String, "10:00")

        let banner = element("banner.open", in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Hinweis auf offene Zuständigkeit fehlt")
        XCTAssertTrue(banner.label.contains("1 offene Zuständigkeit"), banner.label)

        banner.tap()
        tap("claim.Schwimmen", in: app)
        XCTAssertTrue(app.staticTexts["Alles vergeben"].waitForExistence(timeout: 5))
        tap("responsibilities.done", in: app)
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5), "Hinweis bleibt nach Übernahme stehen")

        // Suche: zurück auf heute, dann Treffer öffnet den Tag des Termins.
        tap("nav.previous", in: app)
        XCTAssertFalse(element("event.Schwimmen", in: app).exists)
        tap("toolbar.search", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("schwimm")
        tap("search.result.Schwimmen", in: app)
        XCTAssertTrue(element("event.Schwimmen", in: app).waitForExistence(timeout: 5), "Suche öffnet den Tag nicht")

        // Wochenansicht
        app.buttons["Woche"].tap()
        XCTAssertTrue(element("week.event.Schwimmen", in: app).waitForExistence(timeout: 5))
        app.buttons["Tag"].tap()

        // Löschen (weich) über den Editor
        tap("event.Schwimmen", in: app)
        XCTAssertTrue(app.navigationBars["Termin"].waitForExistence(timeout: 5), "Editor öffnet nicht")
        var swipes = 0
        while !app.buttons["editor.delete"].exists && swipes < 6 { app.swipeUp(); swipes += 1 }
        tap("editor.delete", in: app)
        // Bestätigungsdialog: der zweite "Löschen"-Knopf, nicht der im Formular.
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Löschen' AND identifier != 'editor.delete'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Bestätigung fehlt")
        confirm.tap()
        XCTAssertTrue(element("event.Schwimmen", in: app).waitForNonExistence(timeout: 5), "Termin nicht gelöscht")
    }

    /// Drag & Drop: Termin halten und nach unten ziehen verschiebt ihn später.
    @MainActor
    func testDragMovesAppointmentLater() {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("nav.next", in: app)
        createEvent("Arzt", in: app)
        let block = element("event.Arzt", in: app)
        XCTAssertEqual(block.value as? String, "10:00")

        // Zoomstufe "normal": 52 Punkte je Stunde → 104 Punkte ≈ 2 Stunden.
        let start = block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 104)))

        let moved = NSPredicate(format: "value != '10:00'")
        expectation(for: moved, evaluatedWith: block)
        waitForExpectations(timeout: 5)
        let value = block.value as? String ?? ""
        let hour = Int(value.prefix(2)) ?? 0
        XCTAssertTrue((11...12).contains(hour), "Erwartet etwa 12:00, ist \(value)")
        XCTAssertTrue(value.hasSuffix(":00") || value.hasSuffix(":15") || value.hasSuffix(":30") || value.hasSuffix(":45"),
                      "Nicht auf 15 Minuten gerastet: \(value)")
    }

    /// Wischen blättert die Tage, der Titel der Navigationsleiste wechselt.
    @MainActor
    func testSwipeChangesDay() {
        let app = launchFreshApp()
        completeSetup(in: app)
        let bar = app.navigationBars.firstMatch
        let before = bar.identifier
        app.swipeLeft()
        let changed = NSPredicate(format: "identifier != %@", before)
        expectation(for: changed, evaluatedWith: bar)
        waitForExpectations(timeout: 5)
        app.swipeRight()
        let back = NSPredicate(format: "identifier == %@", before)
        expectation(for: back, evaluatedWith: bar)
        waitForExpectations(timeout: 5)
    }

    /// Kinderansicht: Schalter aus → Kind sieht Erwachsenen-Termine nur als "Belegt",
    /// eigene Termine lesbar, keine Bearbeitung.
    @MainActor
    func testChildPreviewHidesAdultTitles() {
        let app = launchFreshApp()
        completeSetup(in: app)
        addChild("Mia", in: app)
        tap("members.done", in: app)
        tap("nav.next", in: app)
        createEvent("Zahnarzt", in: app)

        // Zweiter Termin auf einem anderen Tag, damit sich die Blöcke nicht überlagern.
        tap("nav.next", in: app)
        createEvent("Turnen", subjects: ["Mia"], deselectMe: true, in: app)
        tap("nav.previous", in: app)

        tap("toolbar.family", in: app)
        setSwitch("members.kidsSeeTitles", on: false, in: app)
        app.swipeUp()
        tap("members.preview.Mia", in: app)

        XCTAssertTrue(element("preview.end", in: app).waitForExistence(timeout: 5), "Vorschau-Hinweis fehlt")
        XCTAssertTrue(element("event.Belegt", in: app).waitForExistence(timeout: 5), "Erwachsenen-Termin nicht als Belegt")
        XCTAssertFalse(element("event.Zahnarzt", in: app).exists, "Titel ist für das Kind sichtbar")
        XCTAssertFalse(element("toolbar.new", in: app).exists, "Kind darf keine Termine anlegen")

        tap("nav.next", in: app)
        XCTAssertTrue(element("event.Turnen", in: app).waitForExistence(timeout: 5), "Kindertermin nicht lesbar")

        tap("preview.end", in: app)
        tap("nav.previous", in: app)
        XCTAssertTrue(element("event.Zahnarzt", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("toolbar.new", in: app).exists)
    }
}
