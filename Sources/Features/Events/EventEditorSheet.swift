import SwiftUI
import CoreData

/// Termin oder Dienst anlegen und bearbeiten. Nur für Erwachsene erreichbar.
struct EventEditorSheet: View {

    let household: CDHousehold
    let author: CDMember
    /// nil = neuer Eintrag
    let event: CDEvent?
    let initialDay: Date

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(fetchRequest: HouseholdService.activeMembersRequest())
    private var members: FetchedResults<CDMember>

    @State private var kind: EventKind = .appointment
    @State private var title = ""
    @State private var startAt = Date()
    @State private var endAt = Date()
    @State private var duration: TimeInterval = 3600
    @State private var subjectIDs: Set<NSManagedObjectID> = []
    @State private var busyOnly = false
    @State private var requiredRoles: Set<ParticipationRole> = []
    @State private var tagID: NSManagedObjectID?
    @State private var locationName = ""
    @State private var notes = ""
    @State private var didLoad = false
    @State private var confirmDelete = false

    private var isNew: Bool { event == nil }

    private var tags: [CDTag] {
        ((household.tags as? Set<CDTag>) ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    private var canSave: Bool {
        endAt > startAt
            && !subjectIDs.isEmpty
            && (busyOnly || !title.trimmed.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(EventKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, new in
                        // Dienste sind standardmäßig nur als "Belegt" sichtbar (Aufgabe 8).
                        if isNew { busyOnly = (new == .statusBlock) }
                    }

                    if !busyOnly {
                        TextField(kind == .statusBlock ? "Bezeichnung, z. B. Frühdienst" : "Titel", text: $title)
                    }
                }

                Section("Zeit") {
                    DatePicker("Beginn", selection: $startAt)
                        .onChange(of: startAt) { _, new in
                            // Dauer beibehalten, wenn der Beginn verschoben wird.
                            endAt = new.addingTimeInterval(duration)
                        }
                    DatePicker("Ende", selection: $endAt, in: startAt...)
                        .onChange(of: endAt) { _, new in
                            duration = max(new.timeIntervalSince(startAt), 15 * 60)
                        }
                }

                Section("Für wen") {
                    ForEach(members, id: \.objectID) { member in
                        Button {
                            toggleSubject(member)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Palette.color(member.colorToken ?? "person1"))
                                    .frame(width: 10, height: 10)
                                Text(member.displayName ?? "")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if subjectIDs.contains(member.objectID) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Für die Familie nur als „Belegt“ zeigen", isOn: $busyOnly)
                } footer: {
                    Text(busyOnly
                         ? "Titel, Ort und Notizen werden nicht gespeichert und verlassen dieses iPhone nicht. Alle sehen nur, dass die Zeit belegt ist."
                         : "Alle im Haushalt sehen Titel, Ort und Notizen.")
                }

                if kind == .appointment {
                    Section {
                        ForEach(ParticipationRole.responsibilityRoles) { role in
                            Toggle(role.label + " nötig", isOn: Binding(
                                get: { requiredRoles.contains(role) },
                                set: { on in
                                    if on { requiredRoles.insert(role) } else { requiredRoles.remove(role) }
                                }))
                        }
                    } header: {
                        Text("Zuständigkeiten")
                    } footer: {
                        Text("Offene Zuständigkeiten erscheinen oben in der Tagesansicht, bis jemand sie übernimmt.")
                    }
                }

                if let event, !assignments(of: event).isEmpty {
                    Section("Übernommen") {
                        ForEach(assignments(of: event), id: \.objectID) { participation in
                            HStack {
                                Text("\(ParticipationRole(rawValue: participation.roleRaw ?? "")?.label ?? ""): \(participation.member?.displayName ?? "")")
                                Spacer()
                                if participation.member?.objectID == author.objectID {
                                    Button("Abgeben", role: .destructive) { giveBack(participation) }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }

                if !busyOnly {
                    Section("Details") {
                        Picker("Kategorie", selection: $tagID) {
                            Text("Keine").tag(NSManagedObjectID?.none)
                            ForEach(tags, id: \.objectID) { tag in
                                Label(tag.name ?? "", systemImage: tag.symbolName ?? "tag")
                                    .tag(Optional(tag.objectID))
                            }
                        }
                        TextField("Ort", text: $locationName)
                        TextField("Notizen", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }

                if !isNew {
                    Section {
                        Button("Löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Neu" : kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { context.rollback(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("Eintrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Laden und Speichern

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        if let event {
            kind = EventKind(rawValue: event.kindRaw ?? "") ?? .appointment
            busyOnly = EventVisibility(rawValue: event.visibilityRaw ?? "") == .busyOnly
            title = busyOnly ? "" : (event.title ?? "")
            startAt = event.startAt ?? Date()
            endAt = event.endAt ?? startAt.addingTimeInterval(3600)
            duration = max(endAt.timeIntervalSince(startAt), 15 * 60)
            subjectIDs = Set(EventService.subjects(of: event).map(\.objectID))
            requiredRoles = Set(RequiredRoles.decode(event.requiredRolesRaw))
            tagID = event.tag?.objectID
            locationName = event.locationName ?? ""
            notes = event.notes ?? ""
        } else {
            startAt = Self.nextFullHour(on: initialDay)
            endAt = startAt.addingTimeInterval(3600)
            subjectIDs = [author.objectID]
        }
    }

    private func save() {
        let subjects = members.filter { subjectIDs.contains($0.objectID) }
        let tag = tags.first { $0.objectID == tagID }
        let roles = kind == .appointment
            ? ParticipationRole.responsibilityRoles.filter { requiredRoles.contains($0) }
            : []
        let visibility: EventVisibility = busyOnly ? .busyOnly : .household

        if let event {
            EventService.update(event, in: context,
                                title: title.trimmed, startAt: startAt, endAt: endAt,
                                subjects: Array(subjects), requiredRoles: roles,
                                kind: kind, visibility: visibility, tag: tag,
                                locationName: locationName.trimmed, notes: notes.trimmed)
        } else {
            EventService.makeEvent(in: context, household: household,
                                   title: title.trimmed, startAt: startAt, endAt: endAt,
                                   createdBy: author, subjects: Array(subjects),
                                   requiredRoles: roles, kind: kind, visibility: visibility,
                                   tag: tag, locationName: locationName.trimmed, notes: notes.trimmed)
        }
        PersistenceController.shared.save(context)
        dismiss()
    }

    private func delete() {
        guard let event else { return }
        EventService.softDelete(event)
        PersistenceController.shared.save(context)
        dismiss()
    }

    /// Übernommene Zuständigkeiten (ohne "Betrifft", ohne abgegebene).
    private func assignments(of event: CDEvent) -> [CDEventParticipation] {
        ((event.participations as? Set<CDEventParticipation>) ?? [])
            .filter { $0.roleRaw != ParticipationRole.subject.rawValue
                      && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined }
            .sorted { ($0.roleRaw ?? "", $0.claimedAt ?? .distantPast) < ($1.roleRaw ?? "", $1.claimedAt ?? .distantPast) }
    }

    /// Eigene Übernahme zurückgeben. Nur der eigene Datensatz wird geändert,
    /// deshalb kein Konflikt mit gleichzeitigen Übernahmen anderer (Regel 5).
    private func giveBack(_ participation: CDEventParticipation) {
        participation.statusRaw = ParticipationStatus.declined.rawValue
        participation.updatedAt = Date()
        PersistenceController.shared.save(context)
    }

    private func toggleSubject(_ member: CDMember) {
        if subjectIDs.contains(member.objectID) {
            subjectIDs.remove(member.objectID)
        } else {
            subjectIDs.insert(member.objectID)
        }
    }

    private static func nextFullHour(on day: Date) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let base = calendar.isDate(day, inSameDayAs: now)
            ? now
            : calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
        let hour = calendar.dateInterval(of: .hour, for: base)?.start ?? base
        return calendar.isDate(day, inSameDayAs: now) ? hour.addingTimeInterval(3600) : hour
    }
}
