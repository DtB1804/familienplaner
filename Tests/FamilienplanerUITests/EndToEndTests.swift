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
        showMode("Woche", in: app)
        XCTAssertTrue(element("week.event.Schwimmen", in: app).waitForExistence(timeout: 5))
        showMode("Tag", in: app)

        // Löschen (weich) über den Editor
        // Antippen zeigt zuerst die Details, "Bearbeiten" öffnet den Editor.
        tap("event.Schwimmen", in: app)
        tap("detail.edit", in: app)
        XCTAssertTrue(element("editor.title", in: app).waitForExistence(timeout: 5), "Editor öffnet nicht")
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

        // Rückgängig stellt die alte Uhrzeit wieder her.
        tap("undo.button", in: app)
        let restored = NSPredicate(format: "value == '10:00'")
        expectation(for: restored, evaluatedWith: block)
        waitForExpectations(timeout: 5)
    }

    /// Datum wählen und zurück zu heute.
    @MainActor
    func testJumpToDateAndBackToToday() {
        let app = launchFreshApp()
        completeSetup(in: app)
        XCTAssertFalse(element("nav.today", in: app).exists)
        tap("nav.next", in: app)
        tap("nav.next", in: app)
        tap("nav.today", in: app)
        XCTAssertTrue(element("nav.today", in: app).waitForNonExistence(timeout: 5), "Nicht zurück bei heute")

        tap("nav.title", in: app)
        XCTAssertTrue(app.navigationBars["Datum wählen"].waitForExistence(timeout: 5), "Datumsauswahl fehlt")
        tap("datepicker.today", in: app)
        XCTAssertTrue(app.navigationBars["Datum wählen"].waitForNonExistence(timeout: 5), "Auswahl schließt nicht")
    }

    /// Der Editor sagt, was zum Sichern fehlt, und der Hinweis verschwindet, sobald es passt.
    @MainActor
    func testEditorExplainsWhatIsMissing() {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("toolbar.new", in: app)
        let hint = element("editor.missing", in: app)
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "Hinweis fehlt")
        XCTAssertTrue(hint.label.contains("Titel"), hint.label)
        type("Chor", into: "editor.title", in: app)
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5), "Hinweis bleibt trotz Titel")
    }

    /// Übernehmen direkt im Termin (Detailansicht), nicht nur über das Banner.
    @MainActor
    func testClaimInsideEditor() {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("nav.next", in: app)
        createEvent("Turnen", roles: ["driveFrom"], in: app)
        XCTAssertTrue(element("banner.open", in: app).waitForExistence(timeout: 5))

        tap("event.Turnen", in: app)
        tap("detail.claim.driveFrom", in: app)
        XCTAssertTrue(element("detail.claim.driveFrom", in: app).waitForNonExistence(timeout: 5), "Übernehmen wirkt nicht")
        tap("detail.done", in: app)
        XCTAssertTrue(element("banner.open", in: app).waitForNonExistence(timeout: 5), "Banner muss verschwinden")
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

    /// Terminserie: wöchentlich anlegen, erscheint in der Folgewoche,
    /// "diesen und alle folgenden" löschen lässt frühere stehen.
    @MainActor
    func testWeeklySeries() {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("nav.next", in: app)

        tap("toolbar.new", in: app)
        type("Chor", into: "editor.title", in: app)
        tap("editor.repeat", in: app)
        let weekly = app.buttons["Wöchentlich"].firstMatch
        XCTAssertTrue(weekly.waitForExistence(timeout: 5), "Auswahl Wöchentlich fehlt")
        weekly.tap()
        tap("editor.save", in: app)
        XCTAssertTrue(element("event.Chor", in: app).waitForExistence(timeout: 5))

        showMode("Woche", in: app)
        tap("nav.next", in: app)
        let nextWeek = element("week.event.Chor", in: app)
        XCTAssertTrue(nextWeek.waitForExistence(timeout: 5), "Serie fehlt in der Folgewoche")

        // Ab der Folgewoche löschen
        nextWeek.tap()
        tap("detail.edit", in: app)
        XCTAssertTrue(element("editor.title", in: app).waitForExistence(timeout: 5), "Editor öffnet nicht")
        var swipes = 0
        while !app.buttons["editor.delete"].exists && swipes < 8 { app.swipeUp(); swipes += 1 }
        tap("editor.delete", in: app)
        tap("scope.delete.following", in: app)
        XCTAssertTrue(nextWeek.waitForNonExistence(timeout: 5), "Folgetermin nicht gelöscht")
        tap("nav.next", in: app)
        XCTAssertFalse(element("week.event.Chor", in: app).waitForExistence(timeout: 2), "Spätere Termine nicht gelöscht")

        tap("nav.previous", in: app)
        tap("nav.previous", in: app)
        XCTAssertTrue(element("week.event.Chor", in: app).waitForExistence(timeout: 5), "Erster Termin darf bleiben")
    }

    /// Serie mit "Holt nötig": Übernehmen fragt nach der Serie, "ganze Serie" schließt
    /// alle offenen Termine der nächsten 14 Tage.
    @MainActor
    func testClaimForWholeSeries() {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("nav.next", in: app)

        tap("toolbar.new", in: app)
        type("Tanzen", into: "editor.title", in: app)
        tap("editor.repeat", in: app)
        app.buttons["Wöchentlich"].firstMatch.tap()
        setSwitch("editor.role.driveFrom", on: true, in: app)
        tap("editor.save", in: app)

        let banner = element("banner.open", in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.contains("2 offene"), "Zwei Serientermine in 14 Tagen erwartet: \(banner.label)")
        banner.tap()
        tap("claim.Tanzen", in: app)
        tap("claimScope.series", in: app)
        let ok = app.alerts.buttons["OK"].firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 5), "Bestätigung fehlt")
        ok.tap()
        XCTAssertTrue(app.staticTexts["Alles vergeben"].waitForExistence(timeout: 5))
        tap("responsibilities.done", in: app)
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
    }

    /// Ganztägig: erscheint in der Leiste über dem Zeitstrahl, nicht als Block.
    @MainActor
    func testAllDayEventShowsInStrip() {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("nav.next", in: app)
        tap("toolbar.new", in: app)
        type("Urlaub", into: "editor.title", in: app)
        setSwitch("editor.allDay", on: true, in: app)
        XCTAssertFalse(app.switches["editor.role.driveFrom"].exists, "Keine Zuständigkeiten bei ganztägig")
        tap("editor.save", in: app)

        XCTAssertTrue(element("allday.Urlaub", in: app).waitForExistence(timeout: 5), "Leiste fehlt")
        XCTAssertFalse(element("event.Urlaub", in: app).exists, "Ganztägig darf kein Block im Zeitstrahl sein")
        showMode("Woche", in: app)
        XCTAssertTrue(element("allday.Urlaub", in: app).waitForExistence(timeout: 5), "Leiste fehlt in der Woche")
    }

    /// Freiraum-Finder: ein Termin morgen 10:00–10:30 teilt den freien Tag, Tippen legt einen Termin an.
    @MainActor
    func testFreeTimeFinder() {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("nav.next", in: app)
        createEvent("Arzt", in: app)

        tap("toolbar.free", in: app)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let tomorrow = formatter.string(from: Date().addingTimeInterval(86_400))
        let afterAppointment = app.buttons["free.slot.\(tomorrow).10:30"].firstMatch
        var swipes = 0
        while !afterAppointment.exists && swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(afterAppointment.exists, "Freie Zeit ab 10:30 fehlt")
        XCTAssertTrue(app.buttons["free.slot.\(tomorrow).07:00"].exists, "Freie Zeit ab 7:00 fehlt")
        afterAppointment.tap()
        XCTAssertTrue(app.navigationBars["Neu"].waitForExistence(timeout: 5), "Editor öffnet nicht")
    }

    /// Seitlich ziehen: Termin wandert in die Spalte einer anderen Person.
    @MainActor
    func testDragToOtherPersonColumn() {
        let app = launchFreshApp()
        completeSetup(in: app)
        addChild("Mia", in: app)
        tap("members.done", in: app)
        tap("nav.next", in: app)
        createEvent("Arzt", in: app)

        let block = element("event.Arzt", in: app)
        let before = block.frame.midX
        let laneWidth = (app.windows.firstMatch.frame.width - 44) / 2
        let start = block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: laneWidth, dy: 0)))

        let deadline = Date().addingTimeInterval(5)
        while block.frame.midX - before < laneWidth / 2 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        if block.frame.midX - before < laneWidth / 2 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Hierarchie nach seitlichem Ziehen"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertGreaterThan(block.frame.midX - before, laneWidth / 2, "Termin nicht in Mias Spalte")
        XCTAssertEqual(block.value as? String, "10:00", "Uhrzeit darf sich beim seitlichen Ziehen nicht ändern")
    }

    /// Haushalt löschen führt zurück zur Einrichtung; danach lässt sich neu anlegen.
    @MainActor
    func testDeleteHouseholdReturnsToSetup() {
        let app = launchFreshApp()
        completeSetup(in: app)
        tap("toolbar.family", in: app)
        var swipes = 0
        while !app.buttons["household.remove"].exists && swipes < 8 { app.swipeUp(); swipes += 1 }
        tap("household.remove", in: app)
        // Stufe 1: Dialog mit Sichern-Angebot, Stufe 2: Haushaltsnamen eintippen.
        XCTAssertTrue(app.buttons["Vorher alle Termine sichern (.ics)"].waitForExistence(timeout: 5), "Sichern-Angebot fehlt")
        tap("household.remove.confirm", in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Namensabfrage fehlt")
        let nameField = alert.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Testfamilie")
        alert.buttons["Endgültig löschen"].tap()
        XCTAssertTrue(app.navigationBars["Einrichten"].waitForExistence(timeout: 10), "Nicht zurück bei Einrichten")
        completeSetup(in: app)
    }
}
