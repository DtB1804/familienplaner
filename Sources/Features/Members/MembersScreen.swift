import SwiftUI
import CoreData
import CloudKit
import UIKit

/// Familie verwalten: Mitglieder anlegen und den Haushalt teilen.
struct MembersScreen: View {

    /// Beobachtet, damit Schalter wie die Kinderansicht sofort den neuen Stand zeigen.
    @ObservedObject var household: CDHousehold

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(fetchRequest: HouseholdService.activeMembersRequest())
    private var members: FetchedResults<CDMember>

    @State private var share: CKShare?
    @State private var showAddMember = false
    @State private var editedMember: CDMember?
    @State private var isPreparingInvite = false
    @State private var errorMessage: String?
    @State private var exportFile: ExportFile?
    @State private var confirmRemoveHousehold = false
    @State private var isRemoving = false
    /// Zweite Stufe beim Löschen: Haushaltsnamen eintippen.
    @State private var askHouseholdName = false
    @State private var typedHouseholdName = ""
    /// Nach dem Anlegen einer Person mit eigenem iPhone gleich einladen.
    @State private var inviteAfterSheet = false

    private var isOwner: Bool { HouseholdService.isOwner(of: household) }

    private var children: [CDMember] { members.filter { $0.role == .child } }

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
                        .accessibilityIdentifier("members.add")
                    }
                }

                if let me = CurrentMember.resolve(in: context, household: household) {
                    Section {
                        NavigationLink {
                            CalendarSourcesScreen(household: household, member: me)
                        } label: {
                            Label("Meine Kalender", systemImage: "calendar")
                        }
                        NavigationLink {
                            ReminderSettingsScreen(isAdult: me.role == .adult) {
                                NotificationCenter.default.post(name: .remindersNeedReschedule, object: nil)
                            }
                        } label: {
                            Label("Erinnerungen", systemImage: "bell")
                        }
                    } footer: {
                        Text("Einstellungen für dieses Gerät: Termine aus den eigenen Kalendern übernehmen (z. B. den Dienstkalender nur als „Belegt“) und Erinnerungen.")
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
                        .accessibilityIdentifier("members.kidsSeeTitles")
                    } header: {
                        Text("Kinderansicht")
                    } footer: {
                        Text("Aus: Kinder sehen Termine der Erwachsenen nur als „Belegt“. Termine, die ein Kind betreffen, bleiben lesbar. Das ist eine Anzeige-Einstellung: Die Daten liegen auch auf den Kinder-iPhones.")
                    }
                }

                if canManage, !children.isEmpty {
                    Section {
                        ForEach(children, id: \.objectID) { child in
                            Button {
                                UserDefaults.standard.set(child.id?.uuidString, forKey: CurrentMember.previewKey)
                                dismiss()
                            } label: {
                                Label("Als \(child.displayName ?? "Kind") ansehen", systemImage: "eye")
                            }
                            .accessibilityIdentifier("members.preview.\(child.displayName ?? "")")
                        }
                    } header: {
                        Text("Vorschau")
                    } footer: {
                        Text("Zeigt diese App so, wie das Kind sie sieht, inklusive Einstellung zur Kinderansicht. Oben erscheint ein Hinweis mit „Beenden“. Bearbeiten ist in der Vorschau gesperrt.")
                    }
                }


                if isOwner && canManage {
                    inviteSection
                } else if !isOwner {
                    Section {
                        Text("Dieser Familienkalender wurde mit dir geteilt. Einladungen verschickt, wer ihn angelegt hat.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        exportCalendar()
                    } label: {
                        Label("Alle Termine exportieren (.ics)", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("backup.export")
                } header: {
                    Text("Sicherung")
                } footer: {
                    Text("Erstellt eine Kalenderdatei mit allen Terminen, die sich in jede Kalender-App importieren lässt. Als Rückfallebene, falls mit iCloud etwas schiefgeht.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmRemoveHousehold = true
                    } label: {
                        HStack {
                            Label(isOwner ? "Haushalt löschen" : "Haushalt verlassen", systemImage: "trash")
                            if isRemoving { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isRemoving || (isOwner && !canManage))
                    .accessibilityIdentifier("household.remove")
                } footer: {
                    Text(isOwner
                         ? "Löscht den Haushalt mit allen Terminen und Mitgliedern in iCloud, auch für alle Eingeladenen. Das lässt sich nicht rückgängig machen. Vorher am besten exportieren."
                         : "Entfernt den Familienkalender von diesem Gerät. Die anderen behalten ihn und können dich neu einladen.")
                }
            }
            .confirmationDialog(isOwner ? "Haushalt endgültig löschen?" : "Haushalt verlassen?",
                                isPresented: $confirmRemoveHousehold, titleVisibility: .visible) {
                if isOwner {
                    Button("Vorher alle Termine sichern (.ics)") { exportCalendar() }
                        .accessibilityIdentifier("household.remove.backup")
                    Button("Weiter zum Löschen", role: .destructive) {
                        typedHouseholdName = ""
                        askHouseholdName = true
                    }
                    .accessibilityIdentifier("household.remove.confirm")
                } else {
                    Button("Verlassen", role: .destructive) {
                        Task { await removeHousehold() }
                    }
                    .accessibilityIdentifier("household.remove.confirm")
                }
            } message: {
                Text(isOwner
                     ? "Alle Termine, Mitglieder und Einstellungen werden für die ganze Familie gelöscht. Das lässt sich nicht rückgängig machen."
                     : "Die Termine verschwinden von diesem Gerät.")
            }
            .alert("Zum Bestätigen den Namen eingeben", isPresented: $askHouseholdName) {
                TextField(household.name ?? "", text: $typedHouseholdName)
                    .accessibilityIdentifier("household.remove.name")
                Button("Endgültig löschen", role: .destructive) {
                    if typedHouseholdName.trimmed.caseInsensitiveCompare((household.name ?? "").trimmed) == .orderedSame {
                        Task { await removeHousehold() }
                    } else {
                        errorMessage = "Der Name stimmt nicht. Es wurde nichts gelöscht."
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Tippe „\(household.name ?? "")“ ein. Danach ist der Familienkalender für alle gelöscht.")
            }
            .sheet(item: $exportFile) { file in
                ActivityView(items: [file.url])
            }
            .navigationTitle("Familie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("members.done")
                }
            }
            .sheet(isPresented: $showAddMember, onDismiss: inviteIfRequested) {
                AddMemberSheet(household: household, canInvite: isOwner) { inviteAfterSheet = true }
            }
            .sheet(item: $editedMember, onDismiss: inviteIfRequested) { member in
                AddMemberSheet(household: household, member: member, canInvite: isOwner) { inviteAfterSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .householdShareFailed)) { note in
                errorMessage = "Apples Einladungsdialog meldet einen Fehler. Schick einen Screenshot dieser Meldung an Claude.\n\n\(note.object as? String ?? "")"
            }
            .alert("Das hat nicht geklappt",
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
            Text("Einladen musst du nur Personen mit eigenem iPhone. Wer kein eigenes iPhone hat, wird von den Erwachsenen mitgepflegt.")
        }
    }

    private func invite() async {
        isPreparingInvite = true
        defer { isPreparingInvite = false }
        do {
            try await SharingService.presentInvitation(for: household)
            await loadShare()
        } catch {
            errorMessage = "Die Einladung konnte nicht vorbereitet werden. Bitte prüfe, ob du in iCloud angemeldet bist und Internet hast. Schick einen Screenshot dieser Meldung an Claude.\n\n\(SharingService.describe(error))"
        }
    }

    private func inviteIfRequested() {
        guard inviteAfterSheet else { return }
        inviteAfterSheet = false
        Task { await invite() }
    }

    private func exportCalendar() {
        let events = (try? context.fetch(ICSExporter.allEventsRequest())) ?? []
        let me = CurrentMember.resolve(in: context, household: household)
        do {
            exportFile = ExportFile(url: try ICSExporter.writeFile(events: events, viewer: me, household: household))
        } catch {
            errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func removeHousehold() async {
        isRemoving = true
        defer { isRemoving = false }
        do {
            try await HouseholdRemoval.remove(household)
        } catch {
            errorMessage = "Das hat nicht geklappt. Bitte prüfe Internet und iCloud-Anmeldung.\n\n\(error.localizedDescription)"
        }
    }

    private func reloadShare() {
        Task { await loadShare() }
    }

    private func loadShare() async {
        share = await SharingService.existingShare(for: household)
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
    /// Nur wer den Haushalt angelegt hat, kann einladen.
    var canInvite: Bool = false
    /// Nach dem Sichern einer Person mit eigenem iPhone: Einladung öffnen.
    var onInvite: (() -> Void)? = nil

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var shortName = ""
    @State private var role: MemberRole = .child
    @State private var hasOwnPhone = false
    @State private var didLoad = false
    @State private var confirmRemove = false

    private var canSave: Bool {
        !name.trimmed.isEmpty && !shortName.trimmed.isEmpty && duplicateHint == nil
    }

    /// Jede Person nur einmal im Haushalt (Familientest 01.10.2026: „Jana“ doppelt angelegt).
    /// Vergleich ohne Groß-/Kleinschreibung und Akzente, nur aktive Mitglieder.
    private var duplicateHint: String? {
        let others = ((household.members as? Set<CDMember>) ?? [])
            .filter { $0.isActive && $0.objectID != member?.objectID }
        func same(_ a: String?, _ b: String) -> Bool {
            guard let a, !b.isEmpty else { return false }
            return a.trimmed.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if let twin = others.first(where: { same($0.displayName, name.trimmed) }) {
            return "„\(twin.displayName ?? "")“ gibt es schon. Zum Einladen den vorhandenen Eintrag öffnen und „Eigenes iPhone“ einschalten."
        }
        if others.contains(where: { same($0.shortName, shortName.trimmed) }) {
            return "Das Kürzel „\(shortName.trimmed)“ ist schon vergeben."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vorname", text: $name)
                        .accessibilityIdentifier("member.name")
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
                } header: {
                    Text("Person")
                } footer: {
                    if let duplicateHint {
                        Text(duplicateHint)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("member.duplicate")
                    }
                }
                Section {
                    Toggle("Eigenes iPhone mit eigener Apple-ID", isOn: $hasOwnPhone)
                } footer: {
                    Text(hasOwnPhone
                         ? (canInvite
                            ? "Nach dem Sichern öffnet sich die Einladung, z. B. per Nachricht. Wer sie annimmt, sieht den Familienkalender auf dem eigenen iPhone."
                            : "Die Einladung verschickt, wer den Haushalt angelegt hat: Familie → Familie einladen.")
                         : "Diese Person erscheint im Kalender, ihre Termine tragen die Erwachsenen ein.")
                }
                if let member, member.id != CurrentMember.id {
                    Section {
                        Button("Aus dem Haushalt entfernen", role: .destructive) { confirmRemove = true }
                    } footer: {
                        Text("Die Person verschwindet aus der Auswahl und ihre Spalte aus der Tagesansicht. Ihre Termine werden nicht gelöscht; die anderen Familienmitglieder sehen sie weiter.")
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
                        .accessibilityIdentifier("member.save")
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
        // Einladen, wenn die Person ein eigenes iPhone hat und noch keins eingetragen war.
        let wasParticipant = member?.accountKind == .participant
        if hasOwnPhone && !wasParticipant && canInvite { onInvite?() }
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
                    Text("Fehlt dein Name? Bitte die Person, die den Familienkalender angelegt hat, dich als Mitglied mit eigenem iPhone einzutragen.")
                }
            }
            .overlay {
                if members.isEmpty {
                    ContentUnavailableView("Familie wird geladen",
                                           systemImage: "icloud.and.arrow.down",
                                           description: Text("Die Daten kommen gerade aus iCloud. Das kann beim ersten Mal etwas dauern."))
                } else if candidates.isEmpty {
                    // Geladen, aber niemand ist als "eigenes iPhone" eingetragen (UX-Prüfung A5).
                    ContentUnavailableView("Dein Name fehlt noch",
                                           systemImage: "person.crop.circle.badge.questionmark",
                                           description: Text("Bitte die Person, die den Familienkalender angelegt hat: Familie → deinen Namen antippen (oder „Mitglied hinzufügen“) → „Eigenes iPhone mit eigener Apple-ID“ einschalten. Danach erscheinst du hier von selbst."))
                        .accessibilityIdentifier("identity.missing")
                }
            }
            .navigationTitle("Wer bist du?")
        }
    }
}

// MARK: - Export

struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Teilen-Blatt von iOS (Sichern in Dateien, AirDrop, Mail …).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
