import EventKit
import CoreData
import os

/// Übernimmt Termine aus den iPhone-Kalendern (EventKit) in den Familienkalender.
///
/// Pro Kalender wählt das Mitglied auf seinem eigenen Gerät, was die Familie sieht:
/// - `hidden`:  nichts wird übernommen (Standard für jeden neuen Kalender)
/// - `busyOnly`: nur "Belegt"; Titel, Ort und Notizen verlassen das Gerät nicht
///               (Projektionsprinzip, CLAUDE.md Regel 2 – z. B. Dienstkalender)
/// - `full`:    mit Titel und Ort
///
/// Kalenderquellen und Spiegel liegen im lokalen Store (Regel 3). Wiederkehrende
/// Termine liefert EventKit als einzelne Vorkommen; der Schlüssel eines Vorkommens ist
/// deshalb Kalendereintrag plus Datum des Vorkommens.
/// Ganztägige Termine werden übernommen und in der Leiste über dem Zeitstrahl gezeigt.
@MainActor
final class CalendarImportService {

    static let shared = CalendarImportService()

    let store = EKEventStore()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                category: "CalendarImport")

    /// Zeitfenster der Übernahme: eine Woche zurück, drei Monate voraus.
    private let daysBack = 7
    private let daysAhead = 90

    // MARK: - Zugriff

    var hasFullAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    var accessWasDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            logger.error("Kalenderzugriff fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Kalender zur Auswahl, ohne den Ausgabekalender "Family Planner" (sonst kämen die
    /// eingetragenen Familientermine als Kopie zurück).
    func calendars() -> [EKCalendar] {
        let exportID = CalendarExportService.shared.exportCalendarIdentifier
        return store.calendars(for: .event).filter {
            $0.calendarIdentifier != exportID && $0.title != CalendarExportService.calendarTitle
        }.sorted {
            ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title)
        }
    }

    // MARK: - Einstellungen je Kalender

    func visibility(of calendar: EKCalendar, member: CDMember,
                    in context: NSManagedObjectContext) -> CalendarVisibility {
        guard let source = source(for: calendar.calendarIdentifier, member: member, in: context),
              source.isEnabled else { return .hidden }
        return CalendarVisibility(rawValue: source.visibilityRaw ?? "") ?? .hidden
    }

    func setVisibility(_ visibility: CalendarVisibility, for calendar: EKCalendar,
                       member: CDMember, household: CDHousehold,
                       in context: NSManagedObjectContext) {
        let now = Date()
        let source = source(for: calendar.calendarIdentifier, member: member, in: context)
            ?? {
                let new = CDCalendarSource(context: context)
                new.id = UUID()
                new.memberID = member.id
                new.ekCalendarIdentifier = calendar.calendarIdentifier
                new.kindRaw = (calendar.type == .subscription ? CalendarSourceKind.ekSubscribed
                                                              : CalendarSourceKind.ekLocal).rawValue
                new.syncDirectionRaw = CalendarSyncDirection.readOnly.rawValue
                new.createdAt = now
                return new
            }()
        source.title = calendar.title
        source.visibilityRaw = visibility.rawValue
        source.isEnabled = visibility != .hidden
        source.updatedAt = now
        sync(household: household, member: member, in: context)
    }

    // MARK: - Abgleich

    /// Gleicht alle Kalender dieses Mitglieds auf diesem Gerät ab. Idempotent.
    func sync(household: CDHousehold, member: CDMember, in context: NSManagedObjectContext) {
        guard hasFullAccess, let memberID = member.id else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let windowStart = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
        let windowEnd = calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today

        let sourcesRequest = NSFetchRequest<CDCalendarSource>(entityName: "CDCalendarSource")
        sourcesRequest.predicate = NSPredicate(format: "memberID == %@", memberID as CVarArg)
        let sources = (try? context.fetch(sourcesRequest)) ?? []

        var mirrors = existingMirrors(memberID: memberID, in: context)
        var created = 0, updated = 0, removed = 0, joined = 0
        let mySourceIDs = Set(sources.compactMap(\.id))
        // Alle übernommenen Termine des Haushalts im Fenster, nach Schlüssel. Damit
        // erkennt der Abgleich Termine aus gemeinsamen Kalendern (z. B. iCloud-Familienkalender),
        // die ein anderes Mitglied schon übernommen hat.
        var byKey = importedByKey(from: windowStart, to: windowEnd, in: context)
        var seenAll = Set<String>()

        for source in sources {
            guard let sourceID = source.id else { continue }
            let visibility = CalendarVisibility(rawValue: source.visibilityRaw ?? "") ?? .hidden
            let imported = importedEvents(sourceID: sourceID, from: windowStart, to: windowEnd, in: context)

            guard source.isEnabled, visibility != .hidden,
                  let identifier = source.ekCalendarIdentifier,
                  identifier != CalendarExportService.shared.exportCalendarIdentifier,
                  let ekCalendar = store.calendar(withIdentifier: identifier),
                  ekCalendar.title != CalendarExportService.calendarTitle else {
                // Kalender abgewählt oder auf dem Gerät nicht mehr vorhanden.
                for event in imported { EventService.softDelete(event); removed += 1 }
                continue
            }

            let eventVisibility: EventVisibility = visibility == .busyOnly ? .busyOnly : .household
            let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd,
                                                     calendars: [ekCalendar])
            var seen = Set<String>()

            for ekEvent in store.events(matching: predicate) {
                guard let ekStart = ekEvent.startDate, let ekEnd = ekEvent.endDate else { continue }
                // Ganztägig: auf ganze Tage 0 Uhr bis 0 Uhr normalisieren (EventKit liefert
                // das Ende je nach Kalender als 23:59:59 oder als 0 Uhr des Folgetags).
                let (start, end) = ekEvent.isAllDay ? EventService.allDaySpan(from: ekStart, to: ekEnd) : (ekStart, ekEnd)
                guard end > start else { continue }
                let key = Self.occurrenceKey(ekEvent)
                // Derselbe Termin in zwei eigenen Kalendern (z. B. eingeladen und im
                // gemeinsamen Kalender): nur einmal übernehmen.
                if seenAll.contains(key) && !seen.contains(key) { continue }
                seen.insert(key)
                seenAll.insert(key)
                let title = (ekEvent.title?.isEmpty == false) ? ekEvent.title! : "Termin"

                if let mirror = mirrors[key],
                   let event = imported.first(where: { $0.id == mirror.eventID }) {
                    if needsUpdate(event, title: title, start: start, end: end,
                                   location: ekEvent.location, visibility: eventVisibility)
                        || event.isAllDay != ekEvent.isAllDay {
                        EventService.update(event, in: context,
                                            title: title, startAt: start, endAt: end,
                                            subjects: Array(Set(EventService.subjects(of: event)).union([member])),
                                            requiredRoles: [],
                                            kind: .appointment, visibility: eventVisibility,
                                            tag: event.tag, locationName: ekEvent.location, notes: nil,
                                            isAllDay: ekEvent.isAllDay)
                        updated += 1
                    }
                    mirror.lastSyncedAt = Date()
                } else if let foreign = byKey[key]?.first(where: {
                    !mySourceIDs.contains($0.sourceCalendarSourceID ?? UUID()) && $0.deletedAt == nil
                }) {
                    // Schon von einem anderen Mitglied übernommen: anhängen statt doppeln.
                    ensureSubject(member, in: foreign, context: context)
                    upsertMirror(&mirrors, key: key, eventID: foreign.id, memberID: memberID,
                                 state: .joined, in: context)
                    joined += 1
                } else {
                    let event = EventService.makeEvent(in: context, household: household,
                                                       title: title, startAt: start, endAt: end,
                                                       createdBy: member, subjects: [member],
                                                       visibility: eventVisibility,
                                                       locationName: ekEvent.location,
                                                       isAllDay: ekEvent.isAllDay)
                    event.originRaw = EventOrigin.imported.rawValue
                    event.sourceCalendarSourceID = sourceID
                    event.externalIdentifier = key
                    byKey[key, default: []].append(event)
                    upsertMirror(&mirrors, key: key, eventID: event.id, memberID: memberID,
                                 state: .synced, in: context)
                    created += 1
                }
            }

            // Im Kalender gelöscht oder verschoben aus dem Fenster heraus.
            for event in imported where !seen.contains(event.externalIdentifier ?? "") {
                EventService.softDelete(event)
                removed += 1
            }
            source.lastSyncedAt = Date()
        }

        // Angehängte Termine, die im eigenen Kalender nicht mehr vorkommen: nur die eigene
        // Beteiligung lösen, der Termin gehört dem anderen Mitglied.
        for (key, mirror) in mirrors where mirror.stateRaw == MirrorState.joined.rawValue && !seenAll.contains(key) {
            if let event = byKey[key]?.first(where: { $0.id == mirror.eventID }) {
                removeSubject(member, from: event, context: context)
            }
            context.delete(mirror)
            mirrors[key] = nil
        }

        // Haben zwei Geräte denselben Termin gleichzeitig übernommen, bevor der Abgleich
        // über iCloud lief, gibt es ihn doppelt. Alle Geräte entscheiden gleich: Es bleibt
        // der mit der kleinsten UUID, die anderen hängen sich an ihn an.
        for key in seenAll {
            let candidates = (byKey[key] ?? []).filter { $0.deletedAt == nil }
            guard candidates.count > 1,
                  let winner = candidates.min(by: { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") })
            else { continue }
            for loser in candidates where loser !== winner
                && mySourceIDs.contains(loser.sourceCalendarSourceID ?? UUID()) {
                EventService.softDelete(loser)
                ensureSubject(member, in: winner, context: context)
                upsertMirror(&mirrors, key: key, eventID: winner.id, memberID: memberID,
                             state: .joined, in: context)
                removed += 1
            }
        }

        if context.hasChanges {
            PersistenceController.shared.save(context)
        }
        logger.info("Kalenderabgleich: \(created) neu, \(updated) geändert, \(joined) angehängt, \(removed) entfernt")
    }

    // MARK: - Hilfsfunktionen

    /// Schlüssel eines Vorkommens. Basis ist die Kennung des Kalenderservers
    /// (`calendarItemExternalIdentifier`), die laut Apple auf allen Geräten gleich ist;
    /// nur so lassen sich Termine aus gemeinsamen Kalendern verschiedener Mitglieder
    /// zusammenführen. Bei Wiederholungen ist sie für alle Vorkommen gleich, deshalb
    /// kommt das Datum des Vorkommens dazu. Ausnahme laut Apple: Exchange-Kalender.
    static func occurrenceKey(_ event: EKEvent) -> String {
        let occurrence = event.occurrenceDate ?? event.startDate ?? Date.distantPast
        let base = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
        return "\(base)|\(Int(occurrence.timeIntervalSince1970))"
    }

    /// Wer aus dem Haushalt übernimmt Termine dieses Kalenders bereits?
    /// Für den Hinweis "wird zusammengeführt" in "Meine Kalender".
    func otherImporters(of calendar: EKCalendar, member: CDMember,
                        in context: NSManagedObjectContext) -> [String] {
        guard hasFullAccess, let memberID = member.id else { return [] }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: [calendar])
        let keys = store.events(matching: predicate).prefix(200).map(Self.occurrenceKey)
        guard !keys.isEmpty else { return [] }
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(
            format: "externalIdentifier IN %@ AND deletedAt == nil AND createdByMemberID != %@",
            Array(keys), memberID as CVarArg)
        let ids = Set(((try? context.fetch(request)) ?? []).compactMap(\.createdByMemberID))
        guard !ids.isEmpty else { return [] }
        let members = NSFetchRequest<CDMember>(entityName: "CDMember")
        members.predicate = NSPredicate(format: "id IN %@", Array(ids))
        return ((try? context.fetch(members)) ?? []).compactMap(\.displayName).sorted()
    }

    private func importedByKey(from start: Date, to end: Date,
                               in context: NSManagedObjectContext) -> [String: [CDEvent]] {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(
            format: "originRaw == %@ AND externalIdentifier != nil AND deletedAt == nil AND endAt > %@ AND startAt < %@",
            EventOrigin.imported.rawValue, start as NSDate, end as NSDate)
        let events = (try? context.fetch(request)) ?? []
        return Dictionary(grouping: events) { $0.externalIdentifier ?? "" }
    }

    private func ensureSubject(_ member: CDMember, in event: CDEvent, context: NSManagedObjectContext) {
        guard !EventService.subjects(of: event).contains(where: { $0.objectID == member.objectID }) else { return }
        EventService.addParticipation(in: context, event: event, member: member, role: .subject)
    }

    private func removeSubject(_ member: CDMember, from event: CDEvent, context: NSManagedObjectContext) {
        let participations = (event.participations as? Set<CDEventParticipation>) ?? []
        for participation in participations
        where participation.member?.objectID == member.objectID
            && participation.roleRaw == ParticipationRole.subject.rawValue {
            context.delete(participation)
        }
    }

    private func upsertMirror(_ mirrors: inout [String: CDLocalEventMirror], key: String, eventID: UUID?,
                              memberID: UUID, state: MirrorState, in context: NSManagedObjectContext) {
        let mirror = mirrors[key] ?? CDLocalEventMirror(context: context)
        if mirror.id == nil {
            mirror.id = UUID()
            mirror.createdAt = Date()
        }
        mirror.memberID = memberID
        mirror.ekEventIdentifier = key
        mirror.eventID = eventID
        mirror.directionRaw = MirrorDirection.import.rawValue
        mirror.stateRaw = state.rawValue
        mirror.lastSyncedAt = Date()
        mirror.updatedAt = Date()
        mirrors[key] = mirror
    }

    private func source(for calendarIdentifier: String, member: CDMember,
                        in context: NSManagedObjectContext) -> CDCalendarSource? {
        guard let memberID = member.id else { return nil }
        let request = NSFetchRequest<CDCalendarSource>(entityName: "CDCalendarSource")
        request.predicate = NSPredicate(format: "memberID == %@ AND ekCalendarIdentifier == %@",
                                        memberID as CVarArg, calendarIdentifier)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func existingMirrors(memberID: UUID, in context: NSManagedObjectContext) -> [String: CDLocalEventMirror] {
        let request = NSFetchRequest<CDLocalEventMirror>(entityName: "CDLocalEventMirror")
        request.predicate = NSPredicate(format: "memberID == %@ AND directionRaw == %@",
                                        memberID as CVarArg, MirrorDirection.import.rawValue)
        let mirrors = (try? context.fetch(request)) ?? []
        var result: [String: CDLocalEventMirror] = [:]
        for mirror in mirrors {
            if let key = mirror.ekEventIdentifier { result[key] = mirror }
        }
        return result
    }

    private func importedEvents(sourceID: UUID, from start: Date, to end: Date,
                                in context: NSManagedObjectContext) -> [CDEvent] {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(
            format: "sourceCalendarSourceID == %@ AND deletedAt == nil AND endAt > %@ AND startAt < %@",
            sourceID as CVarArg, start as NSDate, end as NSDate)
        return (try? context.fetch(request)) ?? []
    }

    private func needsUpdate(_ event: CDEvent, title: String, start: Date, end: Date,
                             location: String?, visibility: EventVisibility) -> Bool {
        let targetTitle = visibility == .busyOnly ? "Belegt" : title
        let targetLocation = visibility == .busyOnly ? nil : (location?.isEmpty == true ? nil : location)
        return event.title != targetTitle
            || event.startAt != start
            || event.endAt != end
            || event.locationName != targetLocation
            || event.visibilityRaw != visibility.rawValue
    }
}
