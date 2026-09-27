import SwiftUI
import CoreData

/// Erste Schritte nach dem Einrichten oder nach dem Annehmen einer Einladung, einmal je Gerät:
/// Wer bin ich? Welche Kalender übernehmen? Erinnerungen an?
struct OnboardingScreen: View {

    static let doneKey = "onboarding.done"

    /// In Oberflächentests nur, wenn ausdrücklich verlangt.
    static var shouldShow: Bool {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return false }
        return !TestMode.isActive || ProcessInfo.processInfo.arguments.contains("-showOnboarding")
    }

    let household: CDHousehold
    let me: CDMember
    let onDone: () -> Void

    @AppStorage(ReminderSettings.eventsEnabledKey) private var eventsEnabled = false
    @AppStorage(ReminderSettings.openEnabledKey) private var openEnabled = false
    @AppStorage(CurrentMember.storageKey) private var currentMemberID: String?
    @State private var notificationsDenied = false

    private var isInvited: Bool { !HouseholdService.isOwner(of: household) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Willkommen, \(me.displayName ?? "")!")
                            .font(.title2.weight(.bold))
                        Text(isInvited
                             ? "Du bist jetzt im Familienkalender „\(household.name ?? "")“ als \(me.role.label)."
                             : "Dein Familienkalender „\(household.name ?? "")“ ist eingerichtet.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                    if isInvited {
                        Button("Das bin ich nicht") {
                            currentMemberID = nil
                            onDone()
                        }
                        .accessibilityIdentifier("onboarding.notMe")
                    }
                } header: {
                    Text("1 · Wer bin ich?")
                }

                Section {
                    NavigationLink {
                        CalendarSourcesScreen(household: household, member: me)
                    } label: {
                        Label("Meine Kalender einrichten", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("onboarding.calendars")
                } header: {
                    Text("2 · Welche Kalender übernehmen?")
                } footer: {
                    Text("Du entscheidest je Kalender: gar nicht, nur als „Belegt“ (z. B. Dienstplan) oder mit Titel. Dort kannst du die Familientermine auch in deinen iPhone-Kalender eintragen lassen. Geht auch später unter Familie → Meine Kalender.")
                }

                Section {
                    Toggle("Vor meinen Terminen erinnern", isOn: $eventsEnabled)
                        .accessibilityIdentifier("onboarding.remindEvents")
                    if me.role == .adult {
                        Toggle("Am Vorabend nachfragen, wer bringt oder holt", isOn: $openEnabled)
                            .accessibilityIdentifier("onboarding.remindOpen")
                    }
                    if notificationsDenied {
                        Text("Mitteilungen sind ausgeschaltet. Erlauben unter Einstellungen → Mitteilungen → Family Planner.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("3 · Erinnerungen")
                } footer: {
                    Text("Später änderbar unter Familie → Erinnerungen.")
                }
            }
            .navigationTitle("Erste Schritte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Los geht’s") {
                        UserDefaults.standard.set(true, forKey: Self.doneKey)
                        NotificationCenter.default.post(name: .remindersNeedReschedule, object: nil)
                        onDone()
                    }
                    .accessibilityIdentifier("onboarding.done")
                }
            }
            .onChange(of: eventsEnabled) { _, on in if on { Task { await askPermission() } } }
            .onChange(of: openEnabled) { _, on in if on { Task { await askPermission() } } }
        }
        .interactiveDismissDisabled()
    }

    private func askPermission() async {
        let granted = await ReminderService.requestAuthorization()
        notificationsDenied = !granted
        if !granted {
            eventsEnabled = false
            openEnabled = false
        }
    }
}
