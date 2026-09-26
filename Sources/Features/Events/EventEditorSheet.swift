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
    @State private var duration: TimeInterval = EventService.defaultDuration
    @State private var subjectIDs: Set<NSManagedObjectID> = []
    @State private var busyOnly = false
    @State private var requiredRoles: Set<ParticipationRole> = []
    @State private var tagID: NSManagedObjectID?
    @State private var locationName = ""
    @State private var notes = ""
    @State private var didLoad = false
    @State private var confirmDelete = false
    @State private var repeatChoice: RepeatChoice = .none
    @State private var hasEnd = false
    @State private var untilDate = Date()
    @State private var originalRule: Recurrence?
    @State private var askSaveScope = false
    @State private var askDeleteScope = false
    @State private var pendingGiveBack: CDEventParticipation?
    @State private var isAllDay = false
    /// Letzter Tag eines ganztägigen Termins (einschließlich).
    @State private var lastDay = Date()

    private var isNew: Bool { event == nil }

    /// Termin gehört zu einer Serie (vor dem Bearbeiten).
    private var isSeries: Bool { originalRule != nil }

    private var currentRule: Recurrence? {
        repeatChoice.rule(startingAt: startAt, until: hasEnd ? untilDate : nil)
    }

    /// Wurde die Wiederholung selbst geändert? Vergleich ohne den Tag im Monat,
    /// der sich beim Verschieben des Beginns mitändert.
    private var ruleChanged: Bool {
        guard let original = originalRule, let current = currentRule else { return (originalRule == nil) != (currentRule == nil) }
        return RepeatChoice(original) != RepeatChoice(current) || !sameDay(original.until, current.until)
    }

    private var tags: [CDTag] {
        ((household.tags as? Set<CDTag>) ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Gespeicherter Beginn und Ende; ganztägig: 0 Uhr bis 0 Uhr nach dem letzten Tag.
    private var saveSpan: (Date, Date) {
        guard isAllDay else { return (startAt, endAt) }
        let calendar = Calendar.current
        let after = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(lastDay, startAt))) ?? lastDay
        return EventService.allDaySpan(from: startAt, to: after)
    }

    private var canSave: Bool {
        (isAllDay || endAt > startAt)
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
                        // Mit Beschriftung, damit das Feld auch ausgefüllt erkennbar bleibt.
                        LabeledContent(kind == .statusBlock ? "Bezeichnung" : "Titel") {
                            TextField(kind == .statusBlock ? "z. B. Frühdienst" : "z. B. Schwimmen",
                                      text: $title)
                                .accessibilityIdentifier("editor.title")
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Zeit") {
                    Toggle("Ganztägig", isOn: $isAllDay)
                        .accessibilityIdentifier("editor.allDay")
                    if isAllDay {
                        DatePicker("Von", selection: $startAt, displayedComponents: .date)
                            .onChange(of: startAt) { _, new in
                                if lastDay < new { lastDay = new }
                            }
                        DatePicker("Bis", selection: $lastDay, in: startAt..., displayedComponents: .date)
                    } else {
                        DatePicker("Beginn", selection: $startAt)
                            .onChange(of: startAt) { _, new in
                                // Dauer beibehalten, mindestens aber 30 Minuten vorschlagen.
                                endAt = new.addingTimeInterval(max(duration, EventService.defaultDuration))
                            }
                        DatePicker("Ende", selection: $endAt, in: startAt...)
                            .onChange(of: endAt) { _, new in
                                duration = max(new.timeIntervalSince(startAt), 5 * 60)
                            }
                    }
                }

                Section {
                    Picker("Wiederholen", selection: $repeatChoice) {
                        ForEach(RepeatChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .accessibilityIdentifier("editor.repeat")
                    if repeatChoice != .none {
                        Toggle("Endet", isOn: $hasEnd)
                            .accessibilityIdentifier("editor.repeatEnds")
                        if hasEnd {
                            DatePicker("Letzter Termin am", selection: $untilDate, in: startAt..., displayedComponents: .date)
                        }
                    }
                } footer: {
                    if isSeries && ruleChanged {
                        Text("Die geänderte Wiederholung gilt ab diesem Termin. Spätere Termine der bisherigen Serie werden ersetzt, übernommene Zuständigkeiten dort entfallen.")
                    } else if repeatChoice != .none && !hasEnd {
                        Text("Termine werden für die nächsten \(SeriesService.horizonWeeks) Wochen angelegt und laufend ergänzt.")
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
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("editor.subject.\(member.displayName ?? "")")
                    }
                }

                Section {
                    Toggle("Für die Familie nur als „Belegt“ zeigen", isOn: $busyOnly)
                } footer: {
                    Text(busyOnly
                         ? "Titel, Ort und Notizen werden nicht gespeichert und verlassen dieses iPhone nicht. Alle sehen nur, dass die Zeit belegt ist."
                         : "Alle im Haushalt sehen Titel, Ort und Notizen.")
                }

                if kind == .appointment && !isAllDay {
                    Section {
                        ForEach(ParticipationRole.responsibilityRoles) { role in
                            Toggle(role.label + " nötig", isOn: Binding(
                                get: { requiredRoles.contains(role) },
                                set: { on in
                                    if on { requiredRoles.insert(role) } else { requiredRoles.remove(role) }
                                }))
                            .accessibilityIdentifier("editor.role.\(role.rawValue)")
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
                                if SeriesService.isSeriesClaim(participation) {
                                    Image(systemName: "repeat")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("für die Serie")
                                }
                                Spacer()
                                if participation.member?.objectID == author.objectID {
                                    Button("Abgeben", role: .destructive) {
                                        if SeriesService.isSeriesClaim(participation) {
                                            pendingGiveBack = participation
                                        } else {
                                            giveBack(participation)
                                        }
                                    }
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
                        LabeledContent("Ort") {
                            TextField("optional", text: $locationName)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Section("Notizen") {
                        TextField("optional", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }

                if !isNew {
                    Section {
                        Button("Löschen", role: .destructive) {
                            if isSeries { askDeleteScope = true } else { confirmDelete = true }
                        }
                            .accessibilityIdentifier("editor.delete")
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
                    Button("Sichern") { requestSave() }.disabled(!canSave)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .confirmationDialog("Eintrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { delete(following: false) }
            }
            .confirmationDialog("Termin einer Serie löschen", isPresented: $askDeleteScope, titleVisibility: .visible) {
                Button("Nur diesen Termin", role: .destructive) { delete(following: false) }
                    .accessibilityIdentifier("scope.delete.one")
                Button("Diesen und alle folgenden", role: .destructive) { delete(following: true) }
                    .accessibilityIdentifier("scope.delete.following")
            }
            .confirmationDialog("Für die Serie übernommen", isPresented: Binding(
                get: { pendingGiveBack != nil }, set: { if !$0 { pendingGiveBack = nil } }),
                titleVisibility: .visible) {
                if let participation = pendingGiveBack {
                    Button("Nur diesen Termin abgeben", role: .destructive) { giveBack(participation) }
                    Button("Diesen und alle folgenden abgeben", role: .destructive) { giveBackFollowing(participation) }
                }
            }
            .confirmationDialog("Termin einer Serie ändern", isPresented: $askSaveScope, titleVisibility: .visible) {
                Button("Nur diesen Termin") { save(following: false) }
                    .accessibilityIdentifier("scope.save.one")
                Button("Diesen und alle folgenden") { save(following: true) }
                    .accessibilityIdentifier("scope.save.following")
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
            duration = max(endAt.timeIntervalSince(startAt), 5 * 60)
            subjectIDs = Set(EventService.subjects(of: event).map(\.objectID))
            requiredRoles = Set(RequiredRoles.decode(event.requiredRolesRaw))
            tagID = event.tag?.objectID
            locationName = event.locationName ?? ""
            notes = event.notes ?? ""
            isAllDay = event.isAllDay
            lastDay = EventService.lastDay(of: event) ?? startAt
            if isAllDay {
                // Beim Umschalten auf Uhrzeit sinnvoll vorbelegen.
                endAt = startAt.addingTimeInterval(EventService.defaultDuration)
                duration = EventService.defaultDuration
            }
            originalRule = SeriesService.rule(of: event)
            repeatChoice = RepeatChoice(originalRule)
            hasEnd = originalRule?.until != nil
            untilDate = originalRule?.until ?? Self.defaultUntil(after: startAt)
        } else {
            startAt = TestMode.isActive
                ? (Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: initialDay) ?? initialDay)
                : Self.nextFullHour(on: initialDay)
            endAt = startAt.addingTimeInterval(EventService.defaultDuration)
            subjectIDs = [author.objectID]
            untilDate = Self.defaultUntil(after: startAt)
            lastDay = startAt
        }
    }

    /// Serie: bei unveränderter Wiederholung fragen, ob nur dieser oder alle folgenden
    /// Termine gemeint sind. Eine geänderte Wiederholung gilt immer ab diesem Termin.
    private func requestSave() {
        if isSeries && !ruleChanged {
            askSaveScope = true
        } else {
            save(following: false)
        }
    }

    private func save(following: Bool) {
        let subjects = members.filter { subjectIDs.contains($0.objectID) }
        let tag = tags.first { $0.objectID == tagID }
        let roles = kind == .appointment && !isAllDay
            ? ParticipationRole.responsibilityRoles.filter { requiredRoles.contains($0) }
            : []
        let visibility: EventVisibility = busyOnly ? .busyOnly : .household
        let (startAt, endAt) = saveSpan

        if let event {
            if isSeries && following && !ruleChanged {
                SeriesService.updateFollowing(from: event, in: context,
                                              title: title.trimmed, startAt: startAt, endAt: endAt,
                                              subjects: Array(subjects), requiredRoles: roles,
                                              kind: kind, visibility: visibility, tag: tag,
                                              locationName: locationName.trimmed, notes: notes.trimmed, isAllDay: isAllDay)
            } else {
                EventService.update(event, in: context,
                                    title: title.trimmed, startAt: startAt, endAt: endAt,
                                    subjects: Array(subjects), requiredRoles: roles,
                                    kind: kind, visibility: visibility, tag: tag,
                                    locationName: locationName.trimmed, notes: notes.trimmed, isAllDay: isAllDay)
                if ruleChanged {
                    // Alte Serie ab hier beenden, dann ggf. neue Serie ab diesem Termin.
                    if isSeries { SeriesService.endSeries(before: event, keepingEvent: true, in: context) }
                    SeriesService.detach(event)
                    if let rule = currentRule { SeriesService.startSeries(from: event, rule: rule, in: context) }
                }
            }
        } else {
            let created = EventService.makeEvent(in: context, household: household,
                                                 title: title.trimmed, startAt: startAt, endAt: endAt,
                                                 createdBy: author, subjects: Array(subjects),
                                                 requiredRoles: roles, kind: kind, visibility: visibility,
                                                 tag: tag, locationName: locationName.trimmed, notes: notes.trimmed, isAllDay: isAllDay)
            if let rule = currentRule { SeriesService.startSeries(from: created, rule: rule, in: context) }
        }
        PersistenceController.shared.save(context)
        dismiss()
    }

    private func delete(following: Bool) {
        guard let event else { return }
        if following {
            SeriesService.endSeries(before: event, keepingEvent: false, in: context)
        } else {
            EventService.softDelete(event)
        }
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

    private func giveBackFollowing(_ participation: CDEventParticipation) {
        guard let event, let member = participation.member,
              let role = ParticipationRole(rawValue: participation.roleRaw ?? "") else { return }
        SeriesService.giveBackFollowing(role: role, from: event, by: member, in: context)
        PersistenceController.shared.save(context)
    }

    private func toggleSubject(_ member: CDMember) {
        if subjectIDs.contains(member.objectID) {
            subjectIDs.remove(member.objectID)
        } else {
            subjectIDs.insert(member.objectID)
        }
    }

    private func sameDay(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return Calendar.current.isDate(a, inSameDayAs: b)
        default: return false
        }
    }

    /// Vorschlag für das Serienende: drei Monate nach dem Beginn.
    private static func defaultUntil(after start: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: 3, to: start) ?? start
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
