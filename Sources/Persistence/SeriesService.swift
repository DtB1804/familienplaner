import CoreData
import Foundation

// MARK: - Wiederholungsregel

/// Wiederholung eines Termins. Gespeichert als Teilmenge von RFC 5545 (iCalendar RRULE)
/// in `CDEvent.recurrenceRule`, z. B. "FREQ=WEEKLY;INTERVAL=2;UNTIL=20270701".
public struct Recurrence: Equatable {

    public enum Frequency: String, CaseIterable {
        case daily = "DAILY"
        case weekdays = "WEEKDAYS"   // gespeichert als FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    public var frequency: Frequency
    public var interval: Int = 1
    /// Tag im Monat für monatliche und jährliche Serien. Fehlt der Tag in einem Monat
    /// (31., 29. Februar), fällt der Termin auf den letzten Tag dieses Monats.
    public var monthDay: Int?
    /// Letzter erlaubter Tag (einschließlich). nil = ohne Ende.
    public var until: Date?

    public init(frequency: Frequency, interval: Int = 1, monthDay: Int? = nil, until: Date? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.monthDay = monthDay
        self.until = until
    }

    // MARK: Speicherform

    public var encoded: String {
        var parts: [String]
        switch frequency {
        case .weekdays: parts = ["FREQ=DAILY", "BYDAY=MO,TU,WE,TH,FR"]
        default: parts = ["FREQ=\(frequency.rawValue)"]
        }
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if let monthDay, frequency == .monthly || frequency == .yearly { parts.append("BYMONTHDAY=\(monthDay)") }
        if let until { parts.append("UNTIL=\(Self.dayFormatter.string(from: until))") }
        return parts.joined(separator: ";")
    }

    public init?(encoded: String?) {
        guard let encoded, !encoded.isEmpty else { return nil }
        var values: [String: String] = [:]
        for part in encoded.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { values[pair[0].uppercased()] = pair[1] }
        }
        guard let freq = values["FREQ"] else { return nil }
        let frequency: Frequency
        if freq == "DAILY", values["BYDAY"] == "MO,TU,WE,TH,FR" {
            frequency = .weekdays
        } else if let f = Frequency(rawValue: freq), f != .weekdays {
            frequency = f
        } else {
            return nil
        }
        self.init(frequency: frequency,
                  interval: Int(values["INTERVAL"] ?? "") ?? 1,
                  monthDay: Int(values["BYMONTHDAY"] ?? ""),
                  until: values["UNTIL"].flatMap { Self.dayFormatter.date(from: String($0.prefix(8))) })
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    // MARK: Termine berechnen

    /// Nächster Termin nach `date`, gleiche Uhrzeit (Wanduhr, auch über die Zeitumstellung).
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)
        case .weekdays:
            var candidate = date
            repeat {
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = next
            } while calendar.isDateInWeekend(candidate)
            return candidate
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * interval, to: date)
        case .monthly, .yearly:
            let unit: Calendar.Component = frequency == .monthly ? .month : .year
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let wantedDay = monthDay ?? parts.day ?? 1
            parts.day = 1
            guard let firstOfMonth = calendar.date(from: parts),
                  let shifted = calendar.date(byAdding: unit, value: interval, to: firstOfMonth),
                  let daysInMonth = calendar.range(of: .day, in: .month, for: shifted)?.count else { return nil }
            var result = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: shifted)
            result.day = min(wantedDay, daysInMonth)
            return calendar.date(from: result)
        }
    }

    /// Alle Termine nach `date` bis einschließlich `limit`, begrenzt durch `until`.
    public func occurrences(after date: Date, through limit: Date, calendar: Calendar = .current,
                            maxCount: Int = 400) -> [Date] {
        var result: [Date] = []
        var current = date
        let lastDay = until.map { calendar.startOfDay(for: $0) }
        while result.count < maxCount, let next = next(after: current, calendar: calendar), next <= limit {
            if let lastDay, calendar.startOfDay(for: next) > lastDay { break }
            result.append(next)
            current = next
        }
        return result
    }
}

// MARK: - Auswahl in der Oberfläche

/// Die Wiederholungen, die der Editor anbietet.
public enum RepeatChoice: String, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, biweekly, monthly, yearly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "Nie"
        case .daily: return "Täglich"
        case .weekdays: return "Werktags (Mo–Fr)"
        case .weekly: return "Wöchentlich"
        case .biweekly: return "Alle 2 Wochen"
        case .monthly: return "Monatlich"
        case .yearly: return "Jährlich"
        }
    }

    public init(_ rule: Recurrence?) {
        guard let rule else { self = .none; return }
        switch rule.frequency {
        case .daily: self = .daily
        case .weekdays: self = .weekdays
        case .weekly: self = rule.interval == 2 ? .biweekly : .weekly
        case .monthly: self = .monthly
        case .yearly: self = .yearly
        }
    }

    public func rule(startingAt start: Date, until: Date?, calendar: Calendar = .current) -> Recurrence? {
        let day = calendar.component(.day, from: start)
        switch self {
        case .none: return nil
        case .daily: return Recurrence(frequency: .daily, until: until)
        case .weekdays: return Recurrence(frequency: .weekdays, until: until)
        case .weekly: return Recurrence(frequency: .weekly, until: until)
        case .biweekly: return Recurrence(frequency: .weekly, interval: 2, until: until)
        case .monthly: return Recurrence(frequency: .monthly, monthDay: day, until: until)
        case .yearly: return Recurrence(frequency: .yearly, monthDay: day, until: until)
        }
    }
}

// MARK: - Serien

/// Terminserien (CLAUDE.md Regel 16).
///
/// Eine Serie besteht aus einzelnen `CDEvent`-Datensätzen mit gemeinsamer `seriesParentID`
/// und der Regel in `recurrenceRule`. Angelegt wird bis zu einem rollierenden Horizont
/// (26 Wochen); beim Start und im Hintergrund wird nachgelegt. Dadurch funktionieren
/// Zuständigkeiten, Verschieben, Suche, Erinnerungen und Watch für jeden Termin einzeln.
/// Ein gelöschter Einzeltermin bleibt als weich gelöschter Datensatz stehen und wird
/// deshalb nicht neu angelegt.
public enum SeriesService {

    public static let horizonWeeks = 26
    /// Nachgelegt wird erst, wenn der letzte Termin näher als 20 Wochen liegt,
    /// dann in einem Schritt bis zum Horizont. So entstehen selten gleichzeitige Nachläufe.
    public static let extendBelowWeeks = 20
    /// Markierung in `CDEventParticipation.note`: Übernahme gilt für die ganze Serie
    /// und wird beim Nachlegen auf neue Termine übertragen.
    public static let seriesClaimNote = "series"

    static func horizon(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 7 * horizonWeeks, to: now) ?? now
    }

    public static func rule(of event: CDEvent) -> Recurrence? {
        guard event.seriesParentID != nil else { return nil }
        return Recurrence(encoded: event.recurrenceRule)
    }

    public static func isSeries(_ event: CDEvent) -> Bool { rule(of: event) != nil }

    /// Macht `event` zum ersten Termin einer neuen Serie und legt die Folgetermine an.
    @discardableResult
    public static func startSeries(from event: CDEvent, rule: Recurrence,
                                   in context: NSManagedObjectContext, now: Date = Date()) -> [CDEvent] {
        guard let start = event.startAt else { return [] }
        event.seriesParentID = UUID()
        event.recurrenceRule = rule.encoded
        event.updatedAt = Date()
        let limit = max(horizon(from: now), start)
        return rule.occurrences(after: start, through: limit).map {
            makeOccurrence(copying: event, startAt: $0, in: context)
        }
    }

    /// Alle Termine der Serie, auch weich gelöschte, nach Beginn sortiert.
    public static func occurrences(ofSeries seriesID: UUID, in context: NSManagedObjectContext) -> [CDEvent] {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "seriesParentID == %@", seriesID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "startAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Dieser Termin und alle späteren derselben Serie (ohne gelöschte).
    public static func following(_ event: CDEvent, in context: NSManagedObjectContext) -> [CDEvent] {
        guard let seriesID = event.seriesParentID, let start = event.startAt else { return [event] }
        let rest = occurrences(ofSeries: seriesID, in: context).filter {
            $0.deletedAt == nil && ($0.startAt ?? .distantPast) >= start && $0.objectID != event.objectID
        }
        return [event] + rest
    }

    /// Änderung "dieser und alle folgenden": gleiche Inhalte, Beginn um dieselbe Differenz
    /// verschoben, neue Dauer. Übernommene Zuständigkeiten bleiben (Regel 5).
    public static func updateFollowing(from event: CDEvent, in context: NSManagedObjectContext,
                                       title: String, startAt: Date, endAt: Date,
                                       subjects: [CDMember], requiredRoles: [ParticipationRole],
                                       kind: EventKind, visibility: EventVisibility, tag: CDTag?,
                                       locationName: String?, notes: String?) {
        guard let oldStart = event.startAt else { return }
        let delta = startAt.timeIntervalSince(oldStart)
        let duration = endAt.timeIntervalSince(startAt)
        for occurrence in following(event, in: context) {
            let newStart = (occurrence.startAt ?? oldStart).addingTimeInterval(delta)
            EventService.update(occurrence, in: context, title: title,
                                startAt: newStart, endAt: newStart.addingTimeInterval(duration),
                                subjects: subjects, requiredRoles: requiredRoles, kind: kind,
                                visibility: visibility, tag: tag, locationName: locationName, notes: notes)
        }
    }

    /// Beendet die Serie vor `event`: frühere Termine bekommen ein Ende (Tag davor),
    /// `event` und alle späteren werden weich gelöscht, außer `keep` ist true für `event`.
    public static func endSeries(before event: CDEvent, keepingEvent keep: Bool,
                                 in context: NSManagedObjectContext, calendar: Calendar = .current) {
        guard let seriesID = event.seriesParentID, let start = event.startAt else { return }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start))
        for occurrence in occurrences(ofSeries: seriesID, in: context) where occurrence.deletedAt == nil {
            if (occurrence.startAt ?? .distantPast) < start {
                guard var rule = Recurrence(encoded: occurrence.recurrenceRule) else { continue }
                rule.until = lastDay
                occurrence.recurrenceRule = rule.encoded
                occurrence.updatedAt = Date()
            } else if occurrence.objectID != event.objectID || !keep {
                EventService.softDelete(occurrence)
            }
        }
    }

    /// Löst `event` aus seiner Serie (danach ein Einzeltermin).
    public static func detach(_ event: CDEvent) {
        event.seriesParentID = nil
        event.recurrenceRule = nil
        event.updatedAt = Date()
    }

    // MARK: Nachlegen und Aufräumen

    /// Legt Folgetermine bis zum Horizont nach. Zuständig ist das Gerät des Mitglieds,
    /// das die Serie angelegt hat; ist es nicht mehr im Haushalt, jeder Erwachsene.
    @discardableResult
    public static func extendAll(household: CDHousehold, me: CDMember?, in context: NSManagedObjectContext,
                                 now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let me, me.role == .adult else { return 0 }
        deduplicate(in: context)

        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "seriesParentID != nil AND recurrenceRule != nil AND household == %@", household)
        request.sortDescriptors = [NSSortDescriptor(key: "startAt", ascending: true)]
        let all = (try? context.fetch(request)) ?? []
        let groups = Dictionary(grouping: all) { $0.seriesParentID! }

        let activeIDs = Set(((household.members as? Set<CDMember>) ?? []).filter(\.isActive).compactMap(\.id))
        let threshold = calendar.date(byAdding: .day, value: 7 * extendBelowWeeks, to: now) ?? now
        let limit = horizon(from: now, calendar: calendar)
        var created = 0

        for (_, events) in groups {
            guard let last = events.last, let lastStart = last.startAt, lastStart < threshold,
                  let template = events.last(where: { $0.deletedAt == nil }),
                  let rule = Recurrence(encoded: template.recurrenceRule) else { continue }
            if let creator = template.createdByMemberID, creator != me.id, activeIDs.contains(creator) { continue }
            let standing = standingClaims(of: template)
            for date in rule.occurrences(after: lastStart, through: limit, calendar: calendar) {
                let occurrence = makeOccurrence(copying: template, startAt: date, in: context)
                for (member, role) in standing {
                    let participation = EventService.addParticipation(in: context, event: occurrence,
                                                                      member: member, role: role)
                    participation.note = seriesClaimNote
                }
                created += 1
            }
        }
        return created
    }

    /// Haben zwei Geräte gleichzeitig nachgelegt, gibt es denselben Termin doppelt.
    /// Es bleibt der mit der kleinsten UUID; Übernahmen der anderen wandern mit.
    @discardableResult
    public static func deduplicate(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "seriesParentID != nil AND deletedAt == nil")
        let events = (try? context.fetch(request)) ?? []
        let groups = Dictionary(grouping: events) { event in
            "\(event.seriesParentID?.uuidString ?? "")|\(Int(event.startAt?.timeIntervalSince1970 ?? 0))"
        }
        var removed = 0
        for (_, duplicates) in groups where duplicates.count > 1 {
            let sorted = duplicates.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
            let keep = sorted[0]
            for other in sorted.dropFirst() {
                for participation in (other.participations as? Set<CDEventParticipation>) ?? []
                where participation.roleRaw != ParticipationRole.subject.rawValue {
                    participation.event = keep
                    participation.updatedAt = Date()
                }
                EventService.softDelete(other)
                removed += 1
            }
        }
        return removed
    }

    /// Übernimmt eine Zuständigkeit für diesen und alle folgenden Termine der Serie,
    /// soweit sie dort verlangt und noch offen ist. Die Übernahme ist als Serienübernahme
    /// markiert und gilt damit auch für später nachgelegte Termine. Liefert die Zahl der Übernahmen.
    @discardableResult
    public static func claimFollowing(role: ParticipationRole, from event: CDEvent, by member: CDMember,
                                      in context: NSManagedObjectContext) -> Int {
        var count = 0
        for occurrence in following(event, in: context)
        where RequiredRoles.decode(occurrence.requiredRolesRaw).contains(role) {
            let mine = ((occurrence.participations as? Set<CDEventParticipation>) ?? []).first {
                $0.roleRaw == role.rawValue && $0.member?.objectID == member.objectID
                    && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined
            }
            if let mine {
                // Schon einzeln übernommen: als Serienübernahme markieren.
                if mine.note != seriesClaimNote { mine.note = seriesClaimNote; mine.updatedAt = Date() }
                continue
            }
            guard !EventService.coveredRoles(of: occurrence).contains(role) else { continue }
            if EventService.claim(role: role, on: occurrence, by: member, in: context) == .claimed,
               let created = mineParticipation(role: role, member: member, in: occurrence) {
                created.note = seriesClaimNote
                count += 1
            }
        }
        return count
    }

    /// Serienübernahme abgeben: eigene Übernahmen dieser Rolle ab `event` werden abgegeben
    /// (Status "abgelehnt", eigener Datensatz, Regel 5). Liefert die Zahl.
    @discardableResult
    public static func giveBackFollowing(role: ParticipationRole, from event: CDEvent, by member: CDMember,
                                         in context: NSManagedObjectContext) -> Int {
        var count = 0
        for occurrence in following(event, in: context) {
            guard let mine = mineParticipation(role: role, member: member, in: occurrence) else { continue }
            mine.statusRaw = ParticipationStatus.declined.rawValue
            mine.updatedAt = Date()
            count += 1
        }
        return count
    }

    /// Ist diese Übernahme Teil einer Serienübernahme?
    public static func isSeriesClaim(_ participation: CDEventParticipation) -> Bool {
        participation.note == seriesClaimNote
    }

    private static func mineParticipation(role: ParticipationRole, member: CDMember,
                                          in event: CDEvent) -> CDEventParticipation? {
        ((event.participations as? Set<CDEventParticipation>) ?? []).first {
            $0.roleRaw == role.rawValue && $0.member?.objectID == member.objectID
                && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined
        }
    }

    /// Serienübernahmen eines Termins, die beim Nachlegen übertragen werden.
    static func standingClaims(of template: CDEvent) -> [(CDMember, ParticipationRole)] {
        ((template.participations as? Set<CDEventParticipation>) ?? []).compactMap { participation in
            guard participation.note == seriesClaimNote,
                  ParticipationStatus(rawValue: participation.statusRaw ?? "") != .declined,
                  let member = participation.member, member.isActive,
                  let role = ParticipationRole(rawValue: participation.roleRaw ?? ""), role != .subject
            else { return nil }
            return (member, role)
        }
    }

    // MARK: Intern

    @discardableResult
    static func makeOccurrence(copying template: CDEvent, startAt: Date,
                               in context: NSManagedObjectContext) -> CDEvent {
        let now = Date()
        let duration = (template.endAt ?? startAt).timeIntervalSince(template.startAt ?? startAt)
        let event = CDEvent(context: context)
        if let household = template.household { PersistenceController.assign(event, toStoreOf: household) }
        event.id = UUID()
        event.household = template.household
        event.kindRaw = template.kindRaw
        event.originRaw = template.originRaw
        event.visibilityRaw = template.visibilityRaw
        event.startAt = startAt
        event.endAt = startAt.addingTimeInterval(max(duration, 0))
        event.isAllDay = template.isAllDay
        event.timeZoneIdentifier = template.timeZoneIdentifier
        event.tag = template.tag
        event.title = template.title
        event.locationName = template.locationName
        event.notes = template.notes
        event.requiredRolesRaw = template.requiredRolesRaw
        event.createdByMemberID = template.createdByMemberID
        event.seriesParentID = template.seriesParentID
        event.recurrenceRule = template.recurrenceRule
        event.createdAt = now
        event.updatedAt = now
        for subject in EventService.subjects(of: template) {
            EventService.addParticipation(in: context, event: event, member: subject, role: .subject)
        }
        return event
    }
}
