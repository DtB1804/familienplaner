import CoreData
import UserNotifications
import os

/// Einstellungen der Erinnerungen. Gerätelokal wie "ich" (CLAUDE.md Regel 12):
/// Jedes Familienmitglied entscheidet auf seinem Gerät selbst.
enum ReminderSettings {
    static let eventsEnabledKey = "reminders.events.enabled"
    static let leadMinutesKey = "reminders.events.leadMinutes"
    static let openEnabledKey = "reminders.open.enabled"
    static let openHourKey = "reminders.open.hour"

    static var eventsEnabled: Bool { UserDefaults.standard.bool(forKey: eventsEnabledKey) }
    static var leadMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: leadMinutesKey)
        return value > 0 ? value : 15
    }
    static var openEnabled: Bool { UserDefaults.standard.bool(forKey: openEnabledKey) }
    static var openHour: Int {
        let value = UserDefaults.standard.integer(forKey: openHourKey)
        return (1...23).contains(value) ? value : 19
    }

    static let leadChoices = [5, 10, 15, 30, 60, 120]
}

/// Lokale Mitteilungen auf diesem Gerät:
/// 1. vor eigenen Terminen und vor übernommenen Zuständigkeiten (Bringen, Holen, Begleiten)
/// 2. am Vorabend, wenn für morgen noch Zuständigkeiten offen sind (nur Erwachsene)
///
/// iOS erlaubt höchstens 64 wartende Mitteilungen je App. Deshalb wird immer nur ein
/// Fenster von sieben Tagen geplant und bei jedem Öffnen und jeder Änderung neu berechnet.
/// Änderungen anderer Familienmitglieder kommen erst an, wenn die App wieder geöffnet wird.
@MainActor
enum ReminderService {

    static let identifierPrefix = "fp."
    static let dayKey = "fp.day"
    private static let horizonDays = 7
    private static let maxRequests = 60

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                       category: "Reminders")

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(me: CDMember?, household: CDHousehold?, in context: NSManagedObjectContext) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) })

        guard let me else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        var requests: [(Date, UNNotificationRequest)] = []
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: horizonDays, to: now) ?? now

        if ReminderSettings.eventsEnabled {
            requests += eventReminders(for: me, household: household, from: now, to: horizon, in: context)
        }
        if ReminderSettings.openEnabled, me.role == .adult {
            requests += openResponsibilityReminders(from: now, in: context)
        }

        let chosen = requests.sorted { $0.0 < $1.0 }.prefix(maxRequests)
        for (_, request) in chosen {
            do { try await center.add(request) } catch {
                logger.error("Erinnerung nicht geplant: \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.info("\(chosen.count) Erinnerungen geplant")
    }

    // MARK: - Vor Terminen

    private static func eventReminders(for me: CDMember, household: CDHousehold?,
                                       from now: Date, to horizon: Date,
                                       in context: NSManagedObjectContext) -> [(Date, UNNotificationRequest)] {
        let lead = TimeInterval(ReminderSettings.leadMinutes * 60)
        let request = EventService.eventsRequest(from: now, to: horizon.addingTimeInterval(lead))
        let events = (try? context.fetch(request)) ?? []
        var result: [(Date, UNNotificationRequest)] = []

        for event in events {
            guard let start = event.startAt, start > now, let eventID = event.id else { continue }
            let roles = myRoles(in: event, me: me)
            guard !roles.isEmpty else { continue }
            let fire = start.addingTimeInterval(-lead)
            guard fire > now else { continue }

            let title = EventPresentation.title(of: event, for: me, in: household)
            let time = start.formatted(date: .omitted, time: .shortened)
            let duties = roles.filter { $0 != .subject }
            let content = UNMutableNotificationContent()
            if duties.isEmpty {
                content.title = title
                content.body = "Um \(time)" + locationSuffix(event, me: me, household: household)
            } else {
                let kids = EventService.subjects(of: event).compactMap(\.displayName).joined(separator: ", ")
                content.title = duties.map(\.label).joined(separator: " und ") + (kids.isEmpty ? "" : " \(kids)")
                content.body = "\(title) um \(time)" + locationSuffix(event, me: me, household: household)
            }
            content.sound = .default
            content.userInfo = [dayKey: start.timeIntervalSince1970]
            result.append((fire, UNNotificationRequest(
                identifier: "\(identifierPrefix)event.\(eventID.uuidString)",
                content: content,
                trigger: trigger(at: fire))))
        }
        return result
    }

    // MARK: - Offene Zuständigkeiten am Vorabend

    /// Vorabend-Abfrage: je offene Zuständigkeit eine Mitteilung mit "Übernehme ich"
    /// (bei Serien zusätzlich "Für die Serie"), direkt aus der Mitteilung heraus.
    private static func openResponsibilityReminders(from now: Date,
                                                    in context: NSManagedObjectContext) -> [(Date, UNNotificationRequest)] {
        let open = (try? EventService.openResponsibilities(within: horizonDays + 1, in: context)) ?? []
        let calendar = Calendar.current
        var perDay: [Date: Int] = [:]
        var result: [(Date, UNNotificationRequest)] = []

        for item in open.sorted(by: { $0.startAt < $1.startAt }) {
            let day = calendar.startOfDay(for: item.startAt)
            guard let eve = calendar.date(byAdding: .day, value: -1, to: day),
                  let fire = calendar.date(bySettingHour: ReminderSettings.openHour, minute: 0, second: 0, of: eve),
                  fire > now, perDay[day, default: 0] < maxOpenPerEvening else { continue }
            perDay[day, default: 0] += 1

            let event = fetchEvent(item.eventID, in: context)
            let kids = event.map { EventService.subjects(of: $0).compactMap(\.displayName).joined(separator: ", ") } ?? ""
            let isSeries = event.map(SeriesService.isSeries) ?? false
            let content = UNMutableNotificationContent()
            content.title = "Wer \(item.role.question) morgen\(kids.isEmpty ? "" : " " + kids)?"
            content.body = "\(item.eventTitle) um \(item.startAt.formatted(date: .omitted, time: .shortened))"
            content.sound = .default
            content.categoryIdentifier = isSeries ? openSeriesCategory : openCategory
            content.userInfo = [dayKey: day.timeIntervalSince1970,
                                eventIDKey: item.eventID.uuidString,
                                roleKey: item.role.rawValue]
            result.append((fire, UNNotificationRequest(
                identifier: "\(identifierPrefix)open.\(item.eventID.uuidString).\(item.role.rawValue)",
                content: content,
                trigger: trigger(at: fire))))
        }
        return result
    }

    // MARK: - Aktionen in Mitteilungen

    static let openCategory = "fp.open"
    static let openSeriesCategory = "fp.open.series"
    static let claimAction = "fp.claim"
    static let claimSeriesAction = "fp.claimSeries"
    static let eventIDKey = "fp.eventID"
    static let roleKey = "fp.role"
    private static let maxOpenPerEvening = 6

    /// Einmal beim Start: Knöpfe der Vorabend-Abfrage anmelden.
    static func registerCategories() {
        let claim = UNNotificationAction(identifier: claimAction, title: "Übernehme ich", options: [])
        let series = UNNotificationAction(identifier: claimSeriesAction, title: "Für die ganze Serie", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: openCategory, actions: [claim], intentIdentifiers: []),
            UNNotificationCategory(identifier: openSeriesCategory, actions: [claim, series], intentIdentifiers: [])
        ])
    }

    /// Knopf in der Mitteilung gedrückt: übernehmen und das Ergebnis als kurze Mitteilung zeigen.
    static func handleAction(_ actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        guard actionIdentifier == claimAction || actionIdentifier == claimSeriesAction,
              let rawID = userInfo[eventIDKey] as? String, let eventID = UUID(uuidString: rawID),
              let rawRole = userInfo[roleKey] as? String, let role = ParticipationRole(rawValue: rawRole)
        else { return }
        let outcome = ClaimActions.claim(eventID: eventID, role: role,
                                         scope: actionIdentifier == claimSeriesAction ? .series : .single)
        let content = UNMutableNotificationContent()
        content.title = outcome.message
        content.body = "\(role.label)"
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "\(identifierPrefix)result.\(UUID().uuidString)",
                                  content: content, trigger: nil))
    }

    private static func fetchEvent(_ id: UUID, in context: NSManagedObjectContext) -> CDEvent? {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    // MARK: - Hilfen

    /// Rollen dieses Mitglieds im Termin (ohne abgegebene Übernahmen).
    private static func myRoles(in event: CDEvent, me: CDMember) -> [ParticipationRole] {
        ((event.participations as? Set<CDEventParticipation>) ?? [])
            .filter { $0.member?.objectID == me.objectID
                      && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined }
            .compactMap { ParticipationRole(rawValue: $0.roleRaw ?? "") }
            .filter { $0 != .informed }
    }

    private static func locationSuffix(_ event: CDEvent, me: CDMember, household: CDHousehold?) -> String {
        guard let location = EventPresentation.location(of: event, for: me, in: household),
              !location.isEmpty else { return "" }
        return " · \(location)"
    }

    private static func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}

extension Notification.Name {
    /// Mitteilung angetippt: Tagesansicht auf diesen Tag stellen (userInfo["day"]: Date).
    static let openDayFromReminder = Notification.Name("openDayFromReminder")
    /// Einstellungen geändert: Erinnerungen neu planen.
    static let remindersNeedReschedule = Notification.Name("remindersNeedReschedule")
}
