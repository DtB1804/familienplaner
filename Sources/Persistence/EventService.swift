import CoreData
import Foundation

/// Termine, Beteiligungen und der Stapel offener Zuständigkeiten.
public enum EventService {

    // MARK: - Abfragen

    /// Termine eines Tages, ohne weich gelöschte Einträge.
    public static func eventsRequest(on day: Date,
                                     calendar: Calendar = .current) -> NSFetchRequest<CDEvent> {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(
            format: "deletedAt == nil AND startAt < %@ AND endAt > %@",
            end as NSDate, start as NSDate)
        request.sortDescriptors = [
            NSSortDescriptor(key: "startAt", ascending: true),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        request.relationshipKeyPathsForPrefetching = ["participations", "participations.member", "tag"]
        return request
    }

    public static func openResponsibilities(within days: Int = 14,
                                            in context: NSManagedObjectContext) throws -> [OpenResponsibility] {
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now

        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(
            format: "deletedAt == nil AND startAt >= %@ AND startAt <= %@ AND requiredRolesRaw != nil AND requiredRolesRaw != ''",
            now as NSDate, horizon as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "startAt", ascending: true)]
        request.relationshipKeyPathsForPrefetching = ["participations"]

        return try context.fetch(request).flatMap { event -> [OpenResponsibility] in
            let required = RequiredRoles.decode(event.requiredRolesRaw)
            let covered = coveredRoles(of: event)
            guard let eventID = event.id, let start = event.startAt else { return [] }
            return required
                .filter { !covered.contains($0) }
                .map { OpenResponsibility(eventID: eventID,
                                          role: $0,
                                          startAt: start,
                                          eventTitle: event.title ?? "Ohne Titel") }
        }
    }

    /// Rollen, für die es mindestens eine nicht abgelehnte Beteiligung gibt.
    public static func coveredRoles(of event: CDEvent) -> Set<ParticipationRole> {
        let participations = (event.participations as? Set<CDEventParticipation>) ?? []
        return Set(participations.compactMap { participation -> ParticipationRole? in
            guard ParticipationStatus(rawValue: participation.statusRaw ?? "") != .declined,
                  let role = ParticipationRole(rawValue: participation.roleRaw ?? "") else { return nil }
            return role
        })
    }

    // MARK: - Schreiben

    @discardableResult
    public static func makeEvent(in context: NSManagedObjectContext,
                                 household: CDHousehold,
                                 title: String,
                                 startAt: Date,
                                 endAt: Date,
                                 createdBy: CDMember,
                                 subjects: [CDMember] = [],
                                 requiredRoles: [ParticipationRole] = [],
                                 kind: EventKind = .appointment,
                                 visibility: EventVisibility = .household,
                                 tag: CDTag? = nil,
                                 locationName: String? = nil,
                                 notes: String? = nil) -> CDEvent {
        let now = Date()
        let event = CDEvent(context: context)
        PersistenceController.assign(event, toStoreOf: household)
        event.id = UUID()
        event.household = household
        event.kindRaw = kind.rawValue
        event.originRaw = EventOrigin.manual.rawValue
        event.visibilityRaw = visibility.rawValue
        event.startAt = startAt
        event.endAt = endAt
        event.isAllDay = false
        event.timeZoneIdentifier = TimeZone.current.identifier
        event.tag = tag
        applyContent(to: event, title: title, visibility: visibility,
                     locationName: locationName, notes: notes)
        event.requiredRolesRaw = RequiredRoles.encode(requiredRoles)
        event.createdByMemberID = createdBy.id
        event.createdAt = now
        event.updatedAt = now

        for subject in subjects {
            addParticipation(in: context, event: event, member: subject, role: .subject)
        }
        return event
    }

    /// Ändert einen vorhandenen Termin. Betroffene Personen werden abgeglichen:
    /// neue bekommen eine Beteiligung, entfernte verlieren sie. Zuständigkeiten
    /// (Bringen, Holen, Begleiten) bleiben unberührt, siehe CLAUDE.md Regel 5.
    public static func update(_ event: CDEvent,
                              in context: NSManagedObjectContext,
                              title: String,
                              startAt: Date,
                              endAt: Date,
                              subjects: [CDMember],
                              requiredRoles: [ParticipationRole],
                              kind: EventKind,
                              visibility: EventVisibility,
                              tag: CDTag?,
                              locationName: String?,
                              notes: String?) {
        event.kindRaw = kind.rawValue
        event.visibilityRaw = visibility.rawValue
        event.startAt = startAt
        event.endAt = endAt
        event.tag = tag
        event.requiredRolesRaw = RequiredRoles.encode(requiredRoles)
        applyContent(to: event, title: title, visibility: visibility,
                     locationName: locationName, notes: notes)
        event.updatedAt = Date()

        let current = ((event.participations as? Set<CDEventParticipation>) ?? [])
            .filter { $0.roleRaw == ParticipationRole.subject.rawValue }
        let wanted = Set(subjects.map(\.objectID))
        for participation in current where !wanted.contains(participation.member?.objectID ?? NSManagedObjectID()) {
            context.delete(participation)
        }
        let present = Set(current.compactMap { $0.member?.objectID })
        for member in subjects where !present.contains(member.objectID) {
            addParticipation(in: context, event: event, member: member, role: .subject)
        }
    }

    /// Projektionsprinzip (CLAUDE.md Regel 2): Bei "nur Belegt" verlassen Titel,
    /// Ort und Notizen das Gerät nicht, sie werden gar nicht erst gespeichert.
    private static func applyContent(to event: CDEvent,
                                     title: String,
                                     visibility: EventVisibility,
                                     locationName: String?,
                                     notes: String?) {
        if visibility == .busyOnly {
            event.title = "Belegt"
            event.locationName = nil
            event.notes = nil
        } else {
            event.title = title
            event.locationName = locationName?.isEmpty == true ? nil : locationName
            event.notes = notes?.isEmpty == true ? nil : notes
        }
    }

    /// Betroffene Personen eines Termins (Rolle "Betrifft").
    public static func subjects(of event: CDEvent) -> [CDMember] {
        ((event.participations as? Set<CDEventParticipation>) ?? [])
            .filter { $0.roleRaw == ParticipationRole.subject.rawValue }
            .compactMap(\.member)
    }

    @discardableResult
    public static func addParticipation(in context: NSManagedObjectContext,
                                        event: CDEvent,
                                        member: CDMember,
                                        role: ParticipationRole,
                                        status: ParticipationStatus = .claimed) -> CDEventParticipation {
        let now = Date()
        let participation = CDEventParticipation(context: context)
        PersistenceController.assign(participation, toStoreOf: event)
        participation.id = UUID()
        participation.event = event
        participation.member = member
        participation.roleRaw = role.rawValue
        participation.statusRaw = status.rawValue
        participation.claimedAt = now
        participation.createdAt = now
        participation.updatedAt = now
        return participation
    }

    /// Übernimmt eine offene Zuständigkeit.
    ///
    /// Bewusst als *neuer* Datensatz, nicht als Änderung eines vorhandenen:
    /// CloudKit löst Konflikte auf Record-Ebene nach "letzter Schreiber gewinnt".
    /// Würden zwei Eltern gleichzeitig denselben Datensatz beschreiben, ginge ein
    /// Claim verloren, ohne dass jemand es merkt. Zwei Datensätze gehen dagegen
    /// nie verloren; die App entscheidet deterministisch über `claimedAt`.
    @discardableResult
    public static func claim(role: ParticipationRole,
                             on event: CDEvent,
                             by member: CDMember,
                             in context: NSManagedObjectContext) -> ClaimResult {
        let existing = (event.participations as? Set<CDEventParticipation>)?
            .filter { $0.roleRaw == role.rawValue
                      && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined } ?? []

        if let winner = earliest(of: existing), winner.member?.id != member.id {
            return .alreadyTaken(by: winner.member?.displayName ?? "jemand anderem")
        }

        addParticipation(in: context, event: event, member: member, role: role)
        return .claimed
    }

    /// Bei gleichzeitigen Claims gewinnt der früheste Zeitstempel.
    /// Bei identischem Zeitstempel entscheidet die UUID, damit alle Geräte
    /// unabhängig voneinander zum selben Ergebnis kommen.
    public static func earliest(of participations: some Collection<CDEventParticipation>) -> CDEventParticipation? {
        participations.min { lhs, rhs in
            let l = lhs.claimedAt ?? .distantFuture
            let r = rhs.claimedAt ?? .distantFuture
            if l != r { return l < r }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }

    public enum ClaimResult: Equatable {
        case claimed
        case alreadyTaken(by: String)
    }

    /// Weiches Löschen. Ein hartes Löschen käme über ein Gerät zurück,
    /// das länger offline war.
    public static func softDelete(_ event: CDEvent) {
        event.deletedAt = Date()
        event.updatedAt = Date()
    }
}
