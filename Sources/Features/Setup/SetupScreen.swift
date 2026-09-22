import SwiftUI

/// Erststart: Haushalt anlegen und sich selbst als ersten Erwachsenen eintragen.
/// Bewusst drei Felder, nicht mehr. Alles Weitere wird später ergänzt.
struct SetupScreen: View {

    let onCreate: (_ householdName: String, _ ownerName: String, _ ownerShortName: String) -> Void

    @State private var householdName = ""
    @State private var ownerName = ""
    @State private var ownerShortName = ""

    private var canContinue: Bool {
        !householdName.trimmed.isEmpty && !ownerName.trimmed.isEmpty && !ownerShortName.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Haushalt") {
                    TextField("Name, z. B. Familie Muster", text: $householdName)
                        .textInputAutocapitalization(.words)
                }
                Section("Sie selbst") {
                    TextField("Vorname", text: $ownerName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: ownerName) { _, new in
                            if ownerShortName.isEmpty { ownerShortName = String(new.prefix(2)) }
                        }
                    TextField("Kürzel für die Tagesansicht", text: $ownerShortName)
                        .onChange(of: ownerShortName) { _, new in
                            if new.count > 3 { ownerShortName = String(new.prefix(3)) }
                        }
                }
                Section {
                    Text("Weitere Familienmitglieder legen Sie danach an. Erst dann wird der Haushalt geteilt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Einrichten")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        onCreate(householdName.trimmed, ownerName.trimmed, ownerShortName.trimmed)
                    }
                    .disabled(!canContinue)
                }
            }
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
