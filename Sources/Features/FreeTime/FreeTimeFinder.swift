import CoreData
import Foundation

/// Freiraum-Finder: Wann haben alle ausgewählten Personen gleichzeitig frei?
///
/// Belegt ist eine Person durch Termine, die sie betreffen, und durch Zuständigkeiten, die
/// sie übernommen hat (Bringen, Holen, Begleiten). Ganztägige Termine belegen nur, wenn sie
/// ein Dienst oder "nur Belegt" sind: Urlaub oder Geburtstag heißt nicht "keine Zeit".
enum FreeTimeFinder {

    struct Interval: Equatable, Hashable {
        var start: Date
        var end: Date
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    enum DayPart: String, CaseIterable, Identifiable {
        case wholeDay, morning, afternoon, evening
        var id: String { rawValue }
        var label: String {
            switch self {
            case .wholeDay: return "Ganzer Tag (7–22 Uhr)"
            case .morning: return "Vormittag (7–12 Uhr)"
            case .afternoon: return "Nachmittag (12–18 Uhr)"
            case .evening: return "Abend (17–22 Uhr)"
            }
        }
        var hours: (Int, Int) {
            switch self {
            case .wholeDay: return (7, 22)
            case .morning: return (7, 12)
            case .afternoon: return (12, 18)
            case .evening: return (17, 22)
            }
        }
    }

    enum Days: String, CaseIterable, Identifiable {
        case all, weekend, weekdays
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Alle Tage"
            case .weekend: return "Nur Wochenende"
            case .weekdays: return "Nur Werktage"
            }
        }
    }

    // MARK: Belegte Zeiten

    /// Belegte Zeiten der ausgewählten Mitglieder, zusammengeführt.
    static func busyIntervals(events: [CDEvent], members: [CDMember],
                              calendar: Calendar = .current) -> [Interval] {
        let ids = Set(members.map(\.objectID))
        var result: [Interval] = []
        for event in events where event.deletedAt == nil {
            guard let start = event.startAt, let end = event.endAt, end > start else { continue }
            if event.isAllDay {
                let blocking = EventKind(rawValue: event.kindRaw ?? "") == .statusBlock
                    || EventVisibility(rawValue: event.visibilityRaw ?? "") == .busyOnly
                guard blocking else { continue }
            }
            let involved = ((event.participations as? Set<CDEventParticipation>) ?? []).contains {
                guard let member = $0.member, ids.contains(member.objectID),
                      ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined,
                      let role = ParticipationRole(rawValue: $0.roleRaw ?? "") else { return false }
                return role != .informed
            }
            if involved { result.append(Interval(start: start, end: end)) }
        }
        return merge(result)
    }

    static func merge(_ intervals: [Interval]) -> [Interval] {
        var merged: [Interval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    // MARK: Freie Zeiten

    /// Freie Zeiten von mindestens `minimum` Länge in den nächsten `days` Tagen,
    /// jeweils innerhalb der Tageszeit. Beginn frühestens jetzt, auf 15 Minuten aufgerundet.
    static func freeSlots(busy: [Interval], now: Date, days: Int, dayPart: DayPart, filter: Days,
                          minimum: TimeInterval, calendar: Calendar = .current) -> [Interval] {
        let merged = merge(busy)
        let earliest = roundUp(now, minutes: 15, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var slots: [Interval] = []

        for offset in 0..<max(days, 0) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekend = calendar.isDateInWeekend(day)
            if filter == .weekend && !weekend || filter == .weekdays && weekend { continue }
            let (fromHour, toHour) = dayPart.hours
            guard var windowStart = calendar.date(bySettingHour: fromHour, minute: 0, second: 0, of: day),
                  let windowEnd = calendar.date(bySettingHour: toHour, minute: 0, second: 0, of: day)
            else { continue }
            windowStart = max(windowStart, earliest)
            guard windowEnd > windowStart else { continue }

            var cursor = windowStart
            for block in merged where block.end > windowStart && block.start < windowEnd {
                if block.start > cursor, block.start.timeIntervalSince(cursor) >= minimum {
                    slots.append(Interval(start: cursor, end: block.start))
                }
                cursor = max(cursor, block.end)
            }
            if windowEnd.timeIntervalSince(cursor) >= minimum {
                slots.append(Interval(start: cursor, end: windowEnd))
            }
        }
        return slots
    }

    /// Auf volle `minutes` aufrunden (Zeitzonen haben Versätze in Vielfachen von 15 Minuten).
    static func roundUp(_ date: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let step = TimeInterval(minutes * 60)
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / step).rounded(.up) * step)
    }
}
