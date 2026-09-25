import Foundation

/// Automatisierte Oberflächentests starten die App mit dem Argument `-uiTesting`.
/// Dann: Daten nur im Arbeitsspeicher (kein iCloud), gerätelokale Einstellungen
/// zurückgesetzt, feste Uhrzeiten für neue Termine. Im normalen Betrieb ohne Wirkung.
/// Unit-Tests laufen in der App als Gastgeber und nutzen denselben Modus.
enum TestMode {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-uiTesting") || isUnitTestHost

    /// Die App läuft als Gastgeber der Unit-Tests (FamilienplanerTests). Auch dann kein iCloud.
    static let isUnitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static func resetLocalState() {
        guard isActive else { return }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("reminders.") || key == CurrentMember.storageKey || key == CurrentMember.previewKey {
            defaults.removeObject(forKey: key)
        }
    }
}
