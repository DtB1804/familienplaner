import SwiftUI
import UserNotifications

/// Erinnerungen für dieses Gerät einstellen.
struct ReminderSettingsScreen: View {

    let isAdult: Bool
    let onChange: () -> Void

    @AppStorage(ReminderSettings.eventsEnabledKey) private var eventsEnabled = false
    @AppStorage(ReminderSettings.leadMinutesKey) private var leadMinutes = 15
    @AppStorage(ReminderSettings.openEnabledKey) private var openEnabled = false
    @AppStorage(ReminderSettings.openHourKey) private var openHour = 19

    @State private var denied = false

    var body: some View {
        Form {
            if denied {
                Section {
                    Text("Mitteilungen sind für Family Planner ausgeschaltet. Sie lassen sich in den iPhone-Einstellungen unter Mitteilungen → Family Planner erlauben.")
                        .font(.footnote)
                }
            }

            Section {
                Toggle("Vor meinen Terminen", isOn: $eventsEnabled)
                if eventsEnabled {
                    Picker("Vorlauf", selection: $leadMinutes) {
                        ForEach(ReminderSettings.leadChoices, id: \.self) { minutes in
                            Text(minutes < 60 ? "\(minutes) Minuten" : "\(minutes / 60) Std.").tag(minutes)
                        }
                    }
                }
            } footer: {
                Text("Gilt für Termine, die Sie betreffen, und für Zuständigkeiten, die Sie übernommen haben, z. B. „Holt Josh – Schwimmen um 15:00“.")
            }

            if isAdult {
                Section {
                    Toggle("Am Vorabend nachfragen", isOn: $openEnabled)
                    if openEnabled {
                        Picker("Uhrzeit", selection: $openHour) {
                            ForEach(17...22, id: \.self) { Text("\($0):00 Uhr").tag($0) }
                        }
                    }
                } footer: {
                    Text("Fragt am Abend vorher, wer bringt, holt oder begleitet, wenn es noch niemand übernommen hat, z. B. „Wer holt morgen?“. Übernehmen geht direkt aus der Mitteilung, bei Serien auch für die ganze Serie.")
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Die Erinnerungen werden auf diesem Gerät geplant. Änderungen anderer Familienmitglieder werden berücksichtigt, sobald Family Planner das nächste Mal geöffnet wird.")
            }
        }
        .navigationTitle("Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: eventsEnabled) { _, on in if on { Task { await ensurePermission() } }; onChange() }
        .onChange(of: openEnabled) { _, on in if on { Task { await ensurePermission() } }; onChange() }
        .onChange(of: leadMinutes) { _, _ in onChange() }
        .onChange(of: openHour) { _, _ in onChange() }
        .task { await refreshDenied() }
    }

    private func ensurePermission() async {
        let granted = await ReminderService.requestAuthorization()
        if !granted {
            eventsEnabled = false
            openEnabled = false
        }
        await refreshDenied()
        onChange()
    }

    private func refreshDenied() async {
        denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
