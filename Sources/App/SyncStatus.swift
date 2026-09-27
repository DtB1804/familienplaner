import CloudKit
import CoreData
import Network
import SwiftUI
import os

/// Zustand des iCloud-Abgleichs, damit niemand unbemerkt auf veraltete Termine vertraut.
///
/// Quellen: Anmeldestatus des iCloud-Kontos (`CKContainer.accountStatus`), Netz
/// (`NWPathMonitor`) und die Abgleich-Ereignisse von `NSPersistentCloudKitContainer`
/// (Fehler wie "iCloud-Speicher voll", letzter erfolgreicher Abgleich).
enum SyncProblem: Equatable {
    case offline
    case noAccount
    case restricted
    case quotaExceeded
    case failed(String)

    var title: String {
        switch self {
        case .offline: return "Offline"
        case .noAccount: return "Nicht bei iCloud angemeldet"
        case .restricted: return "iCloud eingeschränkt"
        case .quotaExceeded: return "iCloud-Speicher voll"
        case .failed: return "Abgleich gestört"
        }
    }

    var explanation: String {
        switch self {
        case .offline:
            return "Keine Internetverbindung. Änderungen bleiben auf diesem Gerät und werden abgeglichen, sobald wieder Netz da ist. Änderungen der anderen siehst du erst dann."
        case .noAccount:
            return "Auf diesem Gerät ist niemand bei iCloud angemeldet. Ohne iCloud sieht die Familie deine Änderungen nicht und du ihre nicht. Einstellungen → dein Name → iCloud."
        case .restricted:
            return "iCloud ist auf diesem Gerät eingeschränkt, z. B. durch Bildschirmzeit oder eine Verwaltung. Der Familienkalender wird nicht abgeglichen."
        case .quotaExceeded:
            return "Der iCloud-Speicher ist voll. Neue Termine werden nicht mehr übertragen. Speicher freigeben unter Einstellungen → dein Name → iCloud → Speicher verwalten."
        case .failed(let reason):
            return "Der letzte Abgleich mit iCloud ist fehlgeschlagen: \(reason) Die App versucht es automatisch erneut."
        }
    }

    var symbol: String {
        switch self {
        case .offline: return "wifi.slash"
        case .noAccount, .restricted: return "person.crop.circle.badge.exclamationmark"
        case .quotaExceeded: return "externaldrive.badge.exclamationmark"
        case .failed: return "exclamationmark.icloud"
        }
    }

    /// Welches Problem wird gezeigt, wenn mehrere zugleich bestehen? Das grundlegendste zuerst.
    static func current(accountStatus: CKAccountStatus?, isOnline: Bool, lastError: Error?) -> SyncProblem? {
        switch accountStatus {
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        default: break
        }
        if !isOnline { return .offline }
        guard let lastError else { return nil }
        let ckError = lastError as? CKError
            ?? (lastError as NSError).userInfo[NSUnderlyingErrorKey].flatMap { $0 as? CKError }
        switch ckError?.code {
        case .quotaExceeded: return .quotaExceeded
        case .notAuthenticated: return .noAccount
        case .networkUnavailable, .networkFailure: return .offline
        default: return .failed(lastError.localizedDescription)
        }
    }
}

@MainActor
final class SyncStatus: ObservableObject {

    static let shared = SyncStatus()

    @Published private(set) var problem: SyncProblem?
    @Published private(set) var lastSuccess: Date?

    private var accountStatus: CKAccountStatus?
    private var isOnline = true
    private var lastError: Error?
    private let monitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner", category: "SyncStatus")

    func start() {
        guard observers.isEmpty, !TestMode.isActive else { return }
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in SyncStatus.shared.setOnline(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "SyncStatus.network"))

        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
            Task { @MainActor in SyncStatus.shared.record(event) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in await SyncStatus.shared.refreshAccount() }
        })
        Task { await refreshAccount() }
    }

    func refreshAccount() async {
        do {
            accountStatus = try await CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier).accountStatus()
        } catch {
            logger.error("iCloud-Status unbekannt: \(error.localizedDescription, privacy: .public)")
            accountStatus = .couldNotDetermine
        }
        update()
    }

    private func setOnline(_ online: Bool) {
        isOnline = online
        update()
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        if event.succeeded {
            lastSuccess = event.endDate
            lastError = nil
        } else if let error = event.error {
            lastError = error
            logger.error("Abgleich fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
        update()
    }

    private func update() {
        problem = SyncProblem.current(accountStatus: accountStatus, isOnline: isOnline, lastError: lastError)
    }
}

/// Hinweis oben in der Tagesansicht, solange der Abgleich gestört ist.
struct SyncBanner: View {
    let problem: SyncProblem
    let lastSuccess: Date?
    @State private var showDetails = false

    var body: some View {
        Button { showDetails = true } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: problem.symbol).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(problem.title).font(.subheadline.weight(.semibold))
                    Text(lastSuccess.map { "Zuletzt abgeglichen \($0.formatted(.relative(presentation: .named).locale(Locale(identifier: "de_DE"))))" }
                         ?? "Termine sind eventuell nicht aktuell")
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "info.circle").accessibilityHidden(true)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .background(Palette.color("person5"))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Zeigt Erklärung und Abhilfe")
        .accessibilityIdentifier("sync.banner")
        .alert(problem.title, isPresented: $showDetails) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem.explanation)
        }
    }
}
