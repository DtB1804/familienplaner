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
/// Ganztägige Termine werden vorerst nicht übernommen (Tagesansicht zeigt nur Zeiten).
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

    func calendars() -> [EKCalendar] {
        store.calendars(for: .event).sorted {
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
        var created = 0, updated = 0, removed = 0

        for source in sources {
            guard let sourceID = source.id else { continue }
            let visibility = CalendarVisibility(rawValue: source.visibilityRaw ?? "") ?? .hidden
            let imported = importedEvents(sourceID: sourceID, from: windowStart, to: windowEnd, in: context)

            guard source.isEnabled, visibility != .hidden,
                  let identifier = source.ekCalendarIdentifier,
                  let ekCalendar = store.calendar(withIdentifier: identifier) else {
                // Kalender abgewählt oder auf dem Gerät nicht mehr vorhanden.
                for event in imported { EventService.softDelete(event); removed += 1 }
                continue
            }

            let eventVisibility: EventVisibility = visibility == .busyOnly ? .busyOnly : .household
            let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd,
                                                     calendars: [ekCalendar])
            var seen = Set<String>()

            for ekEvent in store.events(matching: predicate) where !ekEvent.isAllDay {
                guard let start = ekEvent.startDate, let end = ekEvent.endDate, end > start else { continue }
                let key = Self.occurrenceKey(ekEvent)
                seen.insert(key)
                let title = (ekEvent.title?.isEmpty == false) ? ekEvent.title! : "Termin"

                if let mirror = mirrors[key],
                   let event = imported.first(where: { $0.id == mirror.eventID }) {
                    if needsUpdate(event, title: title, start: start, end: end,
                                   location: ekEvent.location, visibility: eventVisibility) {
                        EventService.update(event, in: context,
                                            title: title, startAt: start, endAt: end,
                                            subjects: [member], requiredRoles: [],
                                            kind: .appointment, visibility: eventVisibility,
                                            tag: event.tag, locationName: ekEvent.location, notes: nil)
                        updated += 1
                    }
                    mirror.lastSyncedAt = Date()
                } else {
                    let event = EventService.makeEvent(in: context, household: household,
                                                       title: title, startAt: start, endAt: end,
                                                       createdBy: member, subjects: [member],
                                                       visibility: eventVisibility,
                                                       locationName: ekEvent.location)
                    event.originRaw = EventOrigin.imported.rawValue
                    event.sourceCalendarSourceID = sourceID
                    event.externalIdentifier = key

                    let mirror = mirrors[key] ?? CDLocalEventMirror(context: context)
                    if mirror.id == nil {
                        mirror.id = UUID()
                        mirror.createdAt = Date()
                    }
                    mirror.memberID = memberID
                    mirror.ekEventIdentifier = key
                    mirror.eventID = event.id
                    mirror.directionRaw = MirrorDirection.import.rawValue
                    mirror.stateRaw = MirrorState.synced.rawValue
                    mirror.lastSyncedAt = Date()
                    mirror.updatedAt = Date()
                    mirrors[key] = mirror
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

        if context.hasChanges {
            PersistenceController.shared.save(context)
        }
        logger.info("Kalenderabgleich: \(created) neu, \(updated) geändert, \(removed) entfernt")
    }

    // MARK: - Hilfsfunktionen

    static func occurrenceKey(_ event: EKEvent) -> String {
        let occurrence = event.occurrenceDate ?? event.startDate ?? Date.distantPast
        return "\(event.calendarItemIdentifier)|\(Int(occurrence.timeIntervalSince1970))"
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
