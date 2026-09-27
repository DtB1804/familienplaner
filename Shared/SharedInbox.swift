import Foundation

/// Eingang für Fotos, die über den Teilen-Knopf (Mail, WhatsApp, Fotos) an Family Planner
/// geschickt werden. Die Teilen-Erweiterung legt die Bilder in der App Group ab, die App
/// nimmt sie beim nächsten Öffnen und zeigt die erkannten Terminvorschläge (Regel 4:
/// übernommen wird nur nach Bestätigung).
enum SharedInbox {

    static var folder: URL? {
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetBridge.appGroup) else { return nil }
        let url = base.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Legt ein Bild ab. Dateiname mit Zeitstempel, damit die Reihenfolge erhalten bleibt.
    @discardableResult
    static func save(_ data: Data, fileExtension: String = "jpg") -> Bool {
        guard let folder else { return false }
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).\(fileExtension)"
        return (try? data.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil
    }

    static var pendingCount: Int { files().count }

    /// Ältestes Bild herausnehmen (Datei wird dabei gelöscht).
    static func takeNext() -> Data? {
        guard let next = files().first, let data = try? Data(contentsOf: next) else { return nil }
        try? FileManager.default.removeItem(at: next)
        return data
    }

    private static func files() -> [URL] {
        guard let folder,
              let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return items.filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
