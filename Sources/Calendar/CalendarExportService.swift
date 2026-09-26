import CoreData
import EventKit
import UIKit
import os

/// Trägt Familientermine in einen eigenen Kalender "Family Planner" der Apple-Kalender-App
/// ein und hält ihn aktuell (Einbahnstraße: bearbeitet wird in Family Planner).
///
/// - Jeder eingetragene Termin trägt als URL `familyplanner://event/<UUID>`. Daran erkennt
///   der Abgleich seine Einträge wieder, auch wenn der Kalender in iCloud liegt und ein
///   zweites Gerät derselben Apple-ID (iPhone und iPad) ebenfalls einträgt. Doppelte werden
///   entfernt.
/// - Der Kalender "Family Planner" wird von der Kalenderübernahme ausgenommen, sonst kämen
///   die Termine als Kopie zurück.
/// - Termine, die aus den eigenen Kalendern dieses Mitglieds stammen, werden nicht
///   eingetragen: Sie stehen dort schon.
/// - Titel und Ort folgen der Kinderansicht und "nur Belegt" (Regel 2).
@MainActor
final class CalendarExportService {

    static let shared = CalendarExportService()

    enum Scope: String, CaseIterable, Identifiable {
        case off, mine, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "Aus"
            case .mine: return "Meine Termine"
            case .all: return "Alle Familientermine"
            }
        }
    }

    static let scopeKey = "export.scope"
    static let calendarIDKey = "export.calendarID"
    static let calendarTitle = "Family Planner"
    static let urlPrefix = "familyplanner://event/"

    static var scope: Scope {
        get { Scope(rawValue: UserDefaults.standard.string(forKey: scopeKey) ?? "") ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: scopeKey) }
    }

    private var store: EKEventStore { CalendarImportService.shared.store }
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                category: "CalendarExport")
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private let daysBack = 7
    private let daysAhead = 180

    /// Kennung des Ausgabekalenders auf diesem Gerät (für die Übernahme ausgeschlossen).
    var exportCalendarIdentifier: String? {
        UserDefaults.standard.string(forKey: Self.calendarIDKey)
    }

    // MARK: - Start und Auslöser

    func start() {
        guard observers.isEmpty, !TestMode.isActive else { return }
        for name in [Notification.Name.NSManagedObjectContextDidSave, .NSPersistentStoreRemoteChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleSync() }
            })
        }
    }

    /// Gebündelt: viele Änderungen hintereinander lösen einen Abgleich aus.
    func scheduleSync() {
        guard Self.scope != .off else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            sync()
        }
    }

    // MARK: - Abgleich

    struct Content: Equatable {
        var title: String
        var start: Date
        var end: Date
        var location: String?
        var notes: String
        var isAllDay = false
    }

    /// Was im iPhone-Kalender steht. Rein, ohne EventKit: testbar.
    static func content(for event: CDEvent, me: CDMember, household: CDHousehold?) -> Content {
        let subjects = EventService.subjects(of: event)
        let title = EventPresentation.title(of: event, for: me, in: household)
        let busy = EventPresentation.isBusyOnly(event, for: me, in: household)
        let participations = ((event.participations as? Set<CDEventParticipation>) ?? [])
            .filter { ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined }
        let myDuties = participations
            .filter { $0.member?.objectID == me.objectID }
            .compactMap { ParticipationRole(rawValue: $0.roleRaw ?? "") }
            .filter { ParticipationRole.responsibilityRoles.contains($0) }
        let names = subjects.compactMap(\.displayName)

        var fullTitle = title
        if !myDuties.isEmpty {
            let others = subjects.filter { $0.objectID != me.objectID }.compactMap(\.displayName)
            fullTitle = myDuties.map(\.label).joined(separator: ", ")
                + (others.isEmpty ? "" : " " + others.joined(separator: ", ")) + " · " + title
        } else if !busy, !names.isEmpty, !(names.count == 1 && subjects.first?.objectID == me.objectID) {
            fullTitle = "\(title) (\(names.joined(separator: ", ")))"
        }

        var lines: [String] = []
        if !names.isEmpty { lines.append("Für: " + names.joined(separator: ", ")) }
        for role in ParticipationRole.responsibilityRoles {
            let holders = participations.filter { $0.roleRaw == role.rawValue }.compactMap { $0.member?.displayName }
            if !holders.isEmpty { lines.append("\(role.label): " + holders.joined(separator: ", ")) }
        }
        let open = RequiredRoles.decode(event.requiredRolesRaw).filter { !EventService.coveredRoles(of: event).contains($0) }
        if !open.isEmpty { lines.append("Noch offen: " + open.map(\.label).joined(separator: ", ")) }
        if !busy, let notes = event.notes, !notes.isEmpty { lines.append(""); lines.append(notes) }
        lines.append("")
        lines.append("Aus Family Planner. Änderungen bitte in der App, hier werden sie überschrieben.")

        return Content(title: fullTitle,
                       start: event.startAt ?? Date(),
                       end: event.endAt ?? event.startAt ?? Date(),
                       location: EventPresentation.location(of: event, for: me, in: household),
                       notes: lines.joined(separator: "\n"),
                       isAllDay: event.isAllDay)
    }

    /// Welche Termine eingetragen werden.
    static func shouldExport(_ event: CDEvent, me: CDMember, scope: Scope,
                             ownSourceIDs: Set<UUID>, joinedEventIDs: Set<UUID>) -> Bool {
        guard scope != .off, event.deletedAt == nil else { return false }
        if let source = event.sourceCalendarSourceID, ownSourceIDs.contains(source) { return false }
        if let id = event.id, joinedEventIDs.contains(id) { return false }
        guard scope == .mine else { return true }
        return ((event.participations as? Set<CDEventParticipation>) ?? []).contains {
            $0.member?.objectID == me.objectID
                && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined
                && $0.roleRaw != ParticipationRole.informed.rawValue
        }
    }

    func sync() {
        let scope = Self.scope
        guard scope != .off, CalendarImportService.shared.hasFullAccess else { return }
        let context = PersistenceController.shared.viewContext
        guard let household = try? HouseholdService.fetchHousehold(in: context),
              let me = CurrentMember.resolve(in: context, household: household),
              let memberID = me.id,
              let calendar = ensureCalendar() else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let windowStart = cal.date(byAdding: .day, value: -daysBack, to: today) ?? today
        let windowEnd = cal.date(byAdding: .day, value: daysAhead, to: today) ?? today

        // Eigene übernommene Kalender und angehängte Termine auslassen.
        let sources = NSFetchRequest<CDCalendarSource>(entityName: "CDCalendarSource")
        sources.predicate = NSPredicate(format: "memberID == %@", memberID as CVarArg)
        let ownSourceIDs = Set(((try? context.fetch(sources)) ?? []).compactMap(\.id))
        let mirrors = NSFetchRequest<CDLocalEventMirror>(entityName: "CDLocalEventMirror")
        mirrors.predicate = NSPredicate(format: "memberID == %@ AND stateRaw == %@",
                                        memberID as CVarArg, MirrorState.joined.rawValue)
        let joined = Set(((try? context.fetch(mirrors)) ?? []).compactMap(\.eventID))

        let events = (try? context.fetch(EventService.eventsRequest(from: windowStart, to: windowEnd))) ?? []
        var wanted: [String: Content] = [:]
        for event in events where Self.shouldExport(event, me: me, scope: scope,
                                                    ownSourceIDs: ownSourceIDs, joinedEventIDs: joined) {
            guard let id = event.id?.uuidString else { continue }
            wanted[id] = Self.content(for: event, me: me, household: household)
        }

        let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: [calendar])
        var existing: [String: EKEvent] = [:]
        var created = 0, updated = 0, removed = 0
        do {
            for ekEvent in store.events(matching: predicate) {
                guard let url = ekEvent.url?.absoluteString, url.hasPrefix(Self.urlPrefix) else { continue }
                let id = String(url.dropFirst(Self.urlPrefix.count))
                if existing[id] != nil || wanted[id] == nil {
                    // Doppelt (zweites Gerät) oder nicht mehr gewünscht
                    try store.remove(ekEvent, span: .thisEvent, commit: false)
                    removed += 1
                } else {
                    existing[id] = ekEvent
                }
            }
            for (id, content) in wanted {
                let ekEvent = existing[id] ?? {
                    let new = EKEvent(eventStore: store)
                    new.calendar = calendar
                    new.url = URL(string: Self.urlPrefix + id)
                    return new
                }()
                let isNew = existing[id] == nil
                guard isNew || differs(ekEvent, content) else { continue }
                ekEvent.title = content.title
                ekEvent.isAllDay = content.isAllDay
                ekEvent.startDate = content.start
                // Ganztägig: EventKit erwartet das Ende im letzten Tag, nicht 0 Uhr danach.
                ekEvent.endDate = content.isAllDay ? content.end.addingTimeInterval(-1) : content.end
                ekEvent.location = content.location
                ekEvent.notes = content.notes
                try store.save(ekEvent, span: .thisEvent, commit: false)
                if isNew { created += 1 } else { updated += 1 }
            }
            if created + updated + removed > 0 { try store.commit() }
            logger.info("iPhone-Kalender: \(created) neu, \(updated) geändert, \(removed) entfernt")
        } catch {
            store.reset()
            logger.error("iPhone-Kalender nicht aktualisiert: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ausschalten: Einträge dieses Geräts aus dem Kalender "Family Planner" entfernen.
    func removeAll() {
        guard CalendarImportService.shared.hasFullAccess,
              let id = exportCalendarIdentifier, let calendar = store.calendar(withIdentifier: id) else { return }
        do {
            try store.removeCalendar(calendar, commit: true)
        } catch {
            logger.error("Kalender nicht entfernt: \(error.localizedDescription, privacy: .public)")
        }
        UserDefaults.standard.removeObject(forKey: Self.calendarIDKey)
    }

    // MARK: - Intern

    private func differs(_ ekEvent: EKEvent, _ content: Content) -> Bool {
        // Zeiten mit Toleranz: EventKit speichert ohne Sekundenbruchteile. Ohne Toleranz
        // würde jeder Abgleich neu schreiben und über die Kalenderübernahme den nächsten auslösen.
        if ekEvent.isAllDay != content.isAllDay { return true }
        if content.isAllDay {
            // Ganztägig nur nach Tagen vergleichen, EventKit gibt das Ende unterschiedlich zurück.
            let span = EventService.allDaySpan(from: ekEvent.startDate ?? .distantPast,
                                               to: ekEvent.endDate ?? .distantPast)
            if span.0 != content.start || span.1 != content.end { return true }
        } else if abs((ekEvent.startDate ?? .distantPast).timeIntervalSince(content.start)) >= 1
                    || abs((ekEvent.endDate ?? .distantPast).timeIntervalSince(content.end)) >= 1 {
            return true
        }
        return ekEvent.title != content.title
            || (ekEvent.location ?? "") != (content.location ?? "")
            || (ekEvent.notes ?? "") != content.notes
    }

    /// Kalender "Family Planner" finden oder anlegen. Bevorzugt in der Quelle, in der
    /// neue Termine landen (meist iCloud), damit iPhone und iPad denselben Kalender teilen.
    private func ensureCalendar() -> EKCalendar? {
        if let id = exportCalendarIdentifier, let calendar = store.calendar(withIdentifier: id),
           calendar.allowsContentModifications {
            return calendar
        }
        if let existing = store.calendars(for: .event).first(where: {
            $0.title == Self.calendarTitle && $0.allowsContentModifications
        }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: Self.calendarIDKey)
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        calendar.cgColor = UIColor(Palette.color("person1")).cgColor
        let candidates = [store.defaultCalendarForNewEvents?.source]
            + store.sources.filter { $0.sourceType == .calDAV || $0.sourceType == .local }.map(Optional.some)
        for source in candidates.compactMap({ $0 }) {
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
                UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.calendarIDKey)
                return calendar
            } catch {
                logger.error("Kalender in \(source.title, privacy: .public) nicht angelegt: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }
}
