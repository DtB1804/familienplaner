import SwiftUI
import CoreData
import CloudKit

/// Familie verwalten: Mitglieder anlegen und den Haushalt teilen.
struct MembersScreen: View {

    let household: CDHousehold

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(fetchRequest: HouseholdService.activeMembersRequest())
    private var members: FetchedResults<CDMember>

    @State private var share: CKShare?
    @State private var showAddMember = false
    @State private var isPreparingInvite = false
    @State private var errorMessage: String?

    private var isOwner: Bool { HouseholdService.isOwner(of: household) }

    private var canManage: Bool {
        CurrentMember.resolve(in: context, household: household)?.role == .adult
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Mitglieder") {
                    ForEach(members, id: \.objectID) { member in
                        MemberRow(member: member,
                                  isMe: member.id == CurrentMember.id)
                    }
                    if canManage {
                        Button {
                            showAddMember = true
                        } label: {
                            Label("Mitglied hinzufügen", systemImage: "person.badge.plus")
                        }
                    }
                }

                if isOwner && canManage {
                    inviteSection
                } else if !isOwner {
                    Section {
                        Text("Dieser Haushalt wurde mit Ihnen geteilt. Einladungen verschickt der Haushalt-Owner.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Familie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddMember) {
                AddMemberSheet(household: household)
            }
            .alert("Einladung nicht möglich",
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { reloadShare() }
            .onReceive(NotificationCenter.default.publisher(for: .householdShareChanged)) { _ in
                reloadShare()
            }
        }
    }

    // MARK: - Einladen

    private var inviteSection: some View {
        Section {
            Button {
                Task { await invite() }
            } label: {
                HStack {
                    Label(share == nil ? "Familie einladen" : "Einladungen verwalten",
                          systemImage: "person.2.badge.gearshape")
                    if isPreparingInvite {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isPreparingInvite)

            if let share {
                ForEach(SharingService.participants(of: share), id: \.self) { participant in
                    ParticipantRow(participant: participant)
                }
            }
        } header: {
            Text("Geteilt mit")
        } footer: {
            Text("Einladen müssen Sie nur Personen mit eigenem iPhone. Wer kein eigenes iPhone hat, wird von den Erwachsenen mitgepflegt.")
        }
    }

    private func invite() async {
        isPreparingInvite = true
        defer { isPreparingInvite = false }
        do {
            try await SharingService.presentInvitation(for: household)
            reloadShare()
        } catch {
            errorMessage = "Bitte prüfen Sie, ob Sie in iCloud angemeldet sind und eine Internetverbindung besteht.\n\n\(error.localizedDescription)"
        }
    }

    private func reloadShare() {
        share = SharingService.existingShare(for: household)
    }
}

// MARK: - Zeilen

private struct MemberRow: View {
    let member: CDMember
    let isMe: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            let tint = Palette.color(member.colorToken ?? "person1")
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay(
                    Text(member.shortName ?? "")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "\(member.displayName ?? "") (ich)" : (member.displayName ?? ""))
                Text("\(member.role.label) · \(member.accountKind.label)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ParticipantRow: View {
    let participant: CKShare.Participant

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var name: String {
        if let components = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter().string(from: components)
            if !formatted.isEmpty { return formatted }
        }
        return participant.userIdentity.lookupInfo?.emailAddress
            ?? participant.userIdentity.lookupInfo?.phoneNumber
            ?? "Eingeladene Person"
    }

    private var status: String {
        switch participant.acceptanceStatus {
        case .accepted: return "Dabei"
        case .pending: return "Eingeladen"
        case .removed: return "Entfernt"
        default: return "Unbekannt"
        }
    }
}

// MARK: - Mitglied hinzufügen

struct AddMemberSheet: View {

    let household: CDHousehold

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var shortName = ""
    @State private var role: MemberRole = .child
    @State private var hasOwnPhone = false

    private var canSave: Bool { !name.trimmed.isEmpty && !shortName.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Vorname", text: $name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: name) { _, new in
                            if shortName.isEmpty { shortName = String(new.prefix(2)) }
                        }
                    TextField("Kürzel für die Tagesansicht", text: $shortName)
                        .onChange(of: shortName) { _, new in
                            if new.count > 3 { shortName = String(new.prefix(3)) }
                        }
                    Picker("Rolle", selection: $role) {
                        Text(MemberRole.adult.label).tag(MemberRole.adult)
                        Text(MemberRole.child.label).tag(MemberRole.child)
                    }
                }
                Section {
                    Toggle("Eigenes iPhone mit eigener Apple-ID", isOn: $hasOwnPhone)
                } footer: {
                    Text(hasOwnPhone
                         ? "Diese Person bekommt anschließend eine Einladung und sieht den Familienkalender auf ihrem iPhone."
                         : "Diese Person erscheint im Kalender, ihre Termine tragen die Erwachsenen ein.")
                }
            }
            .navigationTitle("Neues Mitglied")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let count = (household.members as? Set<CDMember>)?.count ?? 0
        HouseholdService.makeMember(in: context,
                                    household: household,
                                    displayName: name.trimmed,
                                    shortName: shortName.trimmed,
                                    role: role,
                                    accountKind: hasOwnPhone ? .participant : .managed,
                                    colorToken: HouseholdService.nextColorToken(in: context),
                                    sortIndex: count)
        PersistenceController.shared.save(context)
        dismiss()
    }
}

// MARK: - Wer bin ich?

/// Nach Annahme einer Einladung: Das Gerät weiß noch nicht, wem es gehört.
struct IdentityPickerScreen: View {

    let household: CDHousehold
    let onPick: (CDMember) -> Void

    @FetchRequest(fetchRequest: HouseholdService.activeMembersRequest())
    private var members: FetchedResults<CDMember>

    private var candidates: [CDMember] {
        members.filter { $0.accountKind == .participant }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates, id: \.objectID) { member in
                        Button {
                            onPick(member)
                        } label: {
                            MemberRow(member: member, isMe: false)
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Fehlt Ihr Name, bitten Sie den Haushalt-Owner, Sie als Mitglied mit eigenem iPhone anzulegen.")
                }
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("Familie wird geladen",
                                           systemImage: "icloud.and.arrow.down",
                                           description: Text("Die Daten kommen gerade aus iCloud. Das kann beim ersten Mal etwas dauern."))
                }
            }
            .navigationTitle("Wer sind Sie?")
        }
    }
}
