import BackgroundTasks
import CoreData
import os

/// Hintergrundabgleich: hält Kalenderübernahme und Erinnerungen aktuell, auch wenn die
/// App nicht geöffnet wird.
///
/// Zwei Auslöser:
/// 1. **Änderungen anderer Familienmitglieder**: CloudKit weckt die App mit einer stillen
///    Mitteilung, `NSPersistentCloudKitContainer` importiert die Änderung und meldet
///    `NSPersistentStoreRemoteChange`. Daraufhin werden die Erinnerungen neu geplant.
/// 2. **Regelmäßiger Hintergrundlauf** (`BGAppRefreshTask`): gleicht die eigenen
///    iPhone-Kalender ab und plant Erinnerungen neu.
///
/// Wann und wie oft iOS beides zulässt, entscheidet das System (Akku, Nutzung,
/// Stromsparmodus, "Hintergrundaktualisierung" in den Einstellungen). Garantiert ist nichts.
@MainActor
final class BackgroundSync {

    static let shared = BackgroundSync()
    /// Muss in Info.plist unter BGTaskSchedulerPermittedIdentifiers stehen.
    static let refreshIdentifier = "de.barg.familienplaner.calendarRefresh"
    /// Frühester Abstand zwischen zwei Hintergrundläufen.
    private static let refreshInterval: TimeInterval = 60 * 60

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                category: "BackgroundSync")
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    /// Einmal beim Start: auf Änderungen aus iCloud hören.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.remoteChangeArrived() }
        }
    }

    /// Nächsten Hintergrundlauf anmelden (beim Wechsel in den Hintergrund und nach jedem Lauf).
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Hintergrundlauf nicht angemeldet: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Der eigentliche Hintergrundlauf.
    func runRefresh() async {
        scheduleRefresh()
        let context = PersistenceController.shared.viewContext
        guard let household = try? HouseholdService.fetchHousehold(in: context),
              let me = CurrentMember.resolve(in: context, household: household) else { return }
        CalendarImportService.shared.sync(household: household, member: me, in: context)
        extendSeries()
        CalendarExportService.shared.sync()
        await ReminderService.reschedule(me: me, household: household, in: context)
        logger.info("Hintergrundlauf abgeschlossen")
    }

    /// Terminserien bis zum Horizont ergänzen (CLAUDE.md Regel 16).
    func extendSeries() {
        let context = PersistenceController.shared.viewContext
        guard let household = try? HouseholdService.fetchHousehold(in: context),
              let me = CurrentMember.resolve(in: context, household: household) else { return }
        let created = SeriesService.extendAll(household: household, me: me, in: context)
        if context.hasChanges { PersistenceController.shared.save(context) }
        if created > 0 { logger.info("Serien ergänzt: \(created) Termine") }
    }

    // MARK: - Intern

    /// Mehrere Importe kurz hintereinander lösen nur eine Neuplanung aus.
    private func remoteChangeArrived() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let context = PersistenceController.shared.viewContext
            guard let household = try? HouseholdService.fetchHousehold(in: context) else { return }
            let me = CurrentMember.resolve(in: context, household: household)
            await ReminderService.reschedule(me: me, household: household, in: context)
        }
    }
}
