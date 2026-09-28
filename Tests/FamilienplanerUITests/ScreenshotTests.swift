import XCTest

/// Bildschirmfotos für den App Store, mit erfundenen Beispieldaten (`-sampleData`).
/// Läuft nur im Workflow „Screenshots“ (Umgebungsvariable FP_SCREENSHOTS=1), nicht nachts.
final class ScreenshotTests: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    @MainActor
    func testAppStoreScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FP_SCREENSHOTS"] == "1",
                          "Nur im Screenshot-Workflow")
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-sampleData", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        XCTAssertTrue(element("toolbar.family", in: app).waitForExistence(timeout: 15), "Tagesansicht fehlt")
        sleep(1)
        shot("01-Tag", app)

        // Termin antippen: Details mit "Übernehme ich"
        if element("event.Schwimmkurs", in: app).waitForExistence(timeout: 5) {
            element("event.Schwimmkurs", in: app).tap()
            if element("detail.done", in: app).waitForExistence(timeout: 5) {
                sleep(1)
                shot("02-Termin", app)
                element("detail.done", in: app).tap()
            }
        }

        // Offene Zuständigkeiten
        if element("banner.open", in: app).waitForExistence(timeout: 5) {
            element("banner.open", in: app).tap()
            if element("responsibilities.done", in: app).waitForExistence(timeout: 5) {
                sleep(1)
                shot("03-Wer-holt", app)
                element("responsibilities.done", in: app).tap()
            }
        }

        // Woche und Monat
        showMode("Woche", in: app)
        sleep(1)
        shot("04-Woche", app)
        showMode("Monat", in: app)
        sleep(1)
        shot("05-Monat", app)
        showMode("Tag", in: app)

        // Freie Zeit
        if element("toolbar.free", in: app).waitForExistence(timeout: 5) {
            element("toolbar.free", in: app).tap()
            if element("free.done", in: app).waitForExistence(timeout: 5) {
                sleep(1)
                shot("06-Freie-Zeit", app)
                element("free.done", in: app).tap()
            }
        }
    }

    @MainActor
    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
