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
    @State private var editedMember: CDMember?
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
                        if canManage {
                            Button { editedMember = member } label: {
                                MemberRow(member: member, isMe: member.id == CurrentMember.id)
                            }
                            .foregroundStyle(.primary)
                        } else {
                            MemberRow(member: member, isMe: member.id == CurrentMember.id)
                        }
                    }
                    if canManage {
                        Button {
                            showAddMember = true
                        } label: {
                            Label("Mitglied hinzufügen", systemImage: "person.badge.plus")
                        }
                    }
                }

                if let me = CurrentMember.resolve(in: context, household: household) {
                    Section {
                        NavigationLink {
                            CalendarSourcesScreen(household: household, member: me)
                        } label: {
                            Label("Meine Kalender", systemImage: "calendar")
                        }
                    } footer: {
                        Text("Termine aus den Kalendern dieses iPhones in den Familienplaner übernehmen, z. B. den Dienstkalender nur als „Belegt“.")
                    }
                }

                if canManage {
                    Section {
                        Toggle("Kinder sehen Titel der Erwachsenen-Termine", isOn: Binding(
                            get: { household.childrenSeeAdultTitles },
                            set: { newValue in
                                household.childrenSeeAdultTitles = newValue
                                household.updatedAt = Date()
                                PersistenceController.shared.save(context)
                            }))
                    } header: {
                        Text("Kinderansicht")
                    } footer: {
                        Text("Aus: Kinder sehen Termine der Erwachsenen nur als „Belegt“. Termine, die ein Kind betreffen, bleiben lesbar. Das ist eine Anzeige-Einstellung: Die Daten liegen auch auf den Kinder-iPhones.")
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
            .sheet(item: $editedMember) { member in
                AddMemberSheet(household: household, member: member)
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
    /// nil = neues Mitglied, sonst Bearbeiten
    var member: CDMember? = nil

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var shortName = ""
    @State private var role: MemberRole = .child
    @State private var hasOwnPhone = false
    @State private var didLoad = false
    @State private var confirmRemove = false

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
                if let member, member.id != CurrentMember.id {
                    Section {
                        Button("Aus dem Haushalt entfernen", role: .destructive) { confirmRemove = true }
                    } footer: {
                        Text("Die Person verschwindet aus Kalender und Auswahl. Vergangene Termine bleiben erhalten.")
                    }
                }
            }
            .navigationTitle(member == nil ? "Neues Mitglied" : "Mitglied bearbeiten")
            .onAppear(perform: load)
            .confirmationDialog("Mitglied entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) { deactivate() }
            }
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

    private func load() {
        guard !didLoad, let member else { return }
        didLoad = true
        name = member.displayName ?? ""
        shortName = member.shortName ?? ""
        role = member.role
        hasOwnPhone = member.accountKind == .participant
    }

    private func deactivate() {
        guard let member else { return }
        member.isActive = false
        member.updatedAt = Date()
        PersistenceController.shared.save(context)
        dismiss()
    }

    private func save() {
        if let member {
            member.displayName = name.trimmed
            member.shortName = String(shortName.trimmed.prefix(3))
            member.roleRaw = role.rawValue
            member.accountKindRaw = (hasOwnPhone ? MemberAccountKind.participant : .managed).rawValue
            member.updatedAt = Date()
            PersistenceController.shared.save(context)
            dismiss()
            return
        }
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
