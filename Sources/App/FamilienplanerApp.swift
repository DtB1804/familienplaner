import SwiftUI
import CoreData

@main
struct FamilienplanerApp: App {

    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        }
    }
}

struct RootView: View {

    @Environment(\.managedObjectContext) private var context
    @State private var household: CDHousehold?
    @State private var didCheck = false

    var body: some View {
        Group {
            if let household {
                TodayScreen()
                    .environment(\.household, household)
            } else if didCheck {
                SetupScreen { name, owner, shortName in
                    household = try? HouseholdService.bootstrapIfNeeded(
                        in: context,
                        householdName: name,
                        ownerDisplayName: owner,
                        ownerShortName: shortName)
                }
            } else {
                ProgressView().task { load() }
            }
        }
    }

    private func load() {
        household = try? HouseholdService.fetchHousehold(in: context)
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
