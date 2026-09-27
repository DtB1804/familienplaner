import CoreData
import Foundation

/// Sicherung: alle Termine als Kalenderdatei (.ics, RFC 5545). Lässt sich in jede
/// Kalender-App importieren, falls mit iCloud etwas schiefgeht.
enum ICSExporter {

    /// Kalenderdatei aus den Terminen. Titel und Orte so, wie `viewer` sie sieht (Regel 2).
    static func calendar(events: [CDEvent], viewer: CDMember?, household: CDHousehold?,
                         now: Date = Date()) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Family Planner//DE",
                     "CALSCALE:GREGORIAN", "X-WR-CALNAME:Family Planner"]
        for event in events where event.deletedAt == nil {
            guard let id = event.id, let start = event.startAt, let end = event.endAt else { continue }
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(id.uuidString)@familyplanner")
            lines.append("DTSTAMP:\(utc(now))")
            if event.isAllDay {
                lines.append("DTSTART;VALUE=DATE:\(day(start))")
                lines.append("DTEND;VALUE=DATE:\(day(end))")
            } else {
                lines.append("DTSTART:\(utc(start))")
                lines.append("DTEND:\(utc(end))")
            }
            lines.append("SUMMARY:\(escape(EventPresentation.title(of: event, for: viewer, in: household)))")
            if let location = EventPresentation.location(of: event, for: viewer, in: household), !location.isEmpty {
                lines.append("LOCATION:\(escape(location))")
            }
            let description = details(of: event, viewer: viewer, household: household)
            if !description.isEmpty { lines.append("DESCRIPTION:\(escape(description))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.flatMap(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// Schreibt die Datei in einen temporären Ordner und gibt den Pfad zurück.
    static func writeFile(events: [CDEvent], viewer: CDMember?, household: CDHousehold?) throws -> URL {
        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FamilyPlanner-\(stamp).ics")
        try calendar(events: events, viewer: viewer, household: household)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func allEventsRequest() -> NSFetchRequest<CDEvent> {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "startAt", ascending: true)]
        request.relationshipKeyPathsForPrefetching = ["participations", "participations.member"]
        return request
    }

    // MARK: - Hilfen

    private static func details(of event: CDEvent, viewer: CDMember?, household: CDHousehold?) -> String {
        var parts: [String] = []
        let names = EventService.subjects(of: event).compactMap(\.displayName)
        if !names.isEmpty { parts.append("Für: " + names.joined(separator: ", ")) }
        let participations = ((event.participations as? Set<CDEventParticipation>) ?? [])
            .filter { ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined }
        for role in ParticipationRole.responsibilityRoles {
            let who = participations.filter { $0.roleRaw == role.rawValue }.compactMap { $0.member?.displayName }
            if !who.isEmpty { parts.append("\(role.label): " + who.joined(separator: ", ")) }
        }
        if !EventPresentation.isBusyOnly(event, for: viewer, in: household), let notes = event.notes, !notes.isEmpty {
            parts.append(notes)
        }
        return parts.joined(separator: "\n")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Zeilen über 75 Bytes umbrechen (Folgezeilen beginnen mit Leerzeichen), ohne ein
    /// Zeichen zu zerteilen.
    static func fold(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var bytes = 0
        for character in line {
            let size = String(character).utf8.count
            let limit = result.isEmpty ? 75 : 74
            if bytes + size > limit {
                result.append(result.isEmpty ? current : " " + current)
                current = ""
                bytes = 0
            }
            current.append(character)
            bytes += size
        }
        result.append(result.isEmpty ? current : " " + current)
        return result
    }

    private static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}
