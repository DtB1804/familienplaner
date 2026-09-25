import SwiftUI
import CoreData

@main
struct FamilienplanerApp: App {

    /// Nur für die Annahme von Einladungslinks, siehe ShareAcceptance.swift.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let persistence = PersistenceController.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        TestMode.resetLocalState()
        BackgroundSync.shared.start()
        WatchSyncService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundSync.shared.scheduleRefresh() }
        }
        .backgroundTask(.appRefresh(BackgroundSync.refreshIdentifier)) {
            await BackgroundSync.shared.runRefresh()
        }
    }
}

struct RootView: View {

    @Environment(\.managedObjectContext) private var context
    @State private var household: CDHousehold?
    @State private var didCheck = false
    @State private var awaitingSharedHousehold = false
    @AppStorage(CurrentMember.storageKey) private var currentMemberID: String?

    var body: some View {
        Group {
            if let household {
                if hasIdentity(in: household) {
                    TodayScreen()
                        .environment(\.household, household)
                } else {
                    IdentityPickerScreen(household: household) { member in
                        currentMemberID = member.id?.uuidString
                    }
                }
            } else if awaitingSharedHousehold {
                ContentUnavailableView("Einladung angenommen",
                                       systemImage: "icloud.and.arrow.down",
                                       description: Text("Der Familienkalender wird aus iCloud geladen. Das kann beim ersten Mal etwas dauern."))
            } else if didCheck {
                SetupScreen { name, owner, shortName in
                    household = try? HouseholdService.bootstrapIfNeeded(
                        in: context,
                        householdName: name,
                        ownerDisplayName: owner,
                        ownerShortName: shortName)
                    if let ownerID = household?.ownerMemberID {
                        currentMemberID = ownerID.uuidString
                    }
                }
            } else {
                ProgressView().task { load() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .householdShareAccepted)) { _ in
            awaitingSharedHousehold = true
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            // Daten eines geteilten Haushalts kommen asynchron. Neu laden, solange
            // noch kein Haushalt da ist oder gerade eine Einladung angenommen wurde.
            if household == nil || awaitingSharedHousehold { load() }
        }
    }

    private func hasIdentity(in household: CDHousehold) -> Bool {
        _ = currentMemberID   // Abhängigkeit für SwiftUI, damit die Auswahl sofort greift
        return CurrentMember.resolve(in: context, household: household) != nil
    }

    private func load() {
        let loaded = try? HouseholdService.fetchHousehold(in: context)
        if awaitingSharedHousehold,
           let loaded,
           loaded.objectID.persistentStore == PersistenceController.shared.sharedStore {
            awaitingSharedHousehold = false
        }
        household = loaded
        didCheck = true
    }
}

// MARK: - Haushalt im Environment

private struct HouseholdKey: EnvironmentKey {
    static let defaultValue: CDHousehold? = nil
}

extension EnvironmentValues {
    var household: CDHousehold? {
        get { self[HouseholdKey.self] }
        set { self[HouseholdKey.self] = newValue }
    }
}
