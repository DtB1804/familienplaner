import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Übergabe des fertigen Ausschnitts (`WatchSnapshot`) von der App an die Widgets.
///
/// App und Widget-Erweiterung sind getrennte Prozesse. Gemeinsam ist nur der Ordner der
/// App Group. Die App schreibt dort eine JSON-Datei, das Widget liest sie. Kein Core Data
/// und kein CloudKit im Widget (wie bei der Watch, CLAUDE.md Regel 15).
enum WidgetBridge {

    static let appGroup = "group.de.barg.familienplaner"
    static let fileName = "snapshot.json"
    /// Tippen auf ein Widget öffnet diesen Tag: familyplanner://day?t=<Unix-Zeit>
    static let urlScheme = "familyplanner"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func load() -> WatchSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    /// Nur schreiben und neu zeichnen lassen, wenn sich der Inhalt geändert hat.
    static func publish(_ snapshot: WatchSnapshot) {
        guard let url = fileURL else { return }
        var comparable = snapshot
        if let old = load() { comparable.generatedAt = old.generatedAt }
        if let old = load(), old == comparable { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func dayURL(_ date: Date) -> URL? {
        URL(string: "\(urlScheme)://day?t=\(Int(date.timeIntervalSince1970))")
    }

    /// Tag aus einem Widget-Link (familyplanner://day?t=…).
    static func day(from url: URL) -> Date? {
        guard url.scheme == urlScheme, url.host == "day",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "t" })?.value,
              let seconds = TimeInterval(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
