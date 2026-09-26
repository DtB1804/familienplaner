import SwiftUI
import CoreData
import EventKit
import PhotosUI

public struct TodayScreen: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.household) private var household
    @Environment(\.scenePhase) private var scenePhase

    @FetchRequest(fetchRequest: HouseholdService.activeMembersRequest())
    private var members: FetchedResults<CDMember>

    /// Aktualisiert sich selbst bei jeder Änderung, auch bei Sync von anderen Geräten.
    @FetchRequest(fetchRequest: EventService.eventsRequest(on: Date()))
    private var dayEvents: FetchedResults<CDEvent>

    @AppStorage(CurrentMember.storageKey) private var currentMemberID: String?
    /// Vorschau "So sieht ein Kind die App" (nur Anzeige, gerätelokal).
    @AppStorage(CurrentMember.previewKey) private var previewMemberID: String?

    @State private var day = Date()
    @State private var mode: CalendarMode = .day
    @State private var showSearch = false
    @State private var reminderTask: Task<Void, Never>?

    @FetchRequest(fetchRequest: EventService.eventsRequest(from: Date(), to: Date()))
    private var weekEvents: FetchedResults<CDEvent>
    @State private var zoom: DayZoom = .normal
    @State private var selectedMemberIDs: Set<NSManagedObjectID> = []
    @State private var openResponsibilities: [OpenResponsibility] = []
    @State private var showMembers = false
    @State private var editorTarget: EditorTarget?
    @State private var showResponsibilities = false
    @State private var detailEvent: CDEvent?
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoImport: PhotoImport?
    @State private var showSuggestions = false

    @FetchRequest(fetchRequest: SuggestionService.pendingRequest())
    private var pendingSuggestions: FetchedResults<CDSuggestionDraft>

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let preview = previewMember {
                    HStack {
                        Label("Vorschau: So sieht \(preview.displayName ?? "das Kind") die App",
                              systemImage: "eye")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Button("Beenden") { previewMemberID = nil }
                            .accessibilityIdentifier("preview.end")
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)
                    .background(Palette.color("person5").opacity(0.25))
                }
                MemberFilterBar(members: Array(members), selection: $selectedMemberIDs)
                if !openResponsibilities.isEmpty {
                    Button { showResponsibilities = true } label: {
                        OpenResponsibilityBanner(items: openResponsibilities)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("banner.open")
                }
                HStack(spacing: Spacing.m) {
                    Picker("Ansicht", selection: $mode) {
                        Text("Tag").tag(CalendarMode.day)
                        Text("Woche").tag(CalendarMode.week)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("mode")
                    // Zoom auch ohne Zwei-Finger-Geste erreichbar.
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { zoom = zoom.zoomedOut() }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(!zoom.canZoomOut)
                    .accessibilityLabel("Verkleinern")
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { zoom = zoom.zoomedIn() }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(!zoom.canZoomIn)
                    .accessibilityLabel("Vergrößern")
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .background(Palette.surface)
                let allDay = (mode == .day ? Array(dayEvents) : Array(weekEvents))
                    .filter { $0.isAllDay && isVisibleInFilter($0) }
                if !allDay.isEmpty {
                    AllDayStrip(events: allDay, showsDates: mode == .week,
                                viewer: viewer, household: household,
                                onSelect: { event in open(event) })
                }
                if mode == .day {
                    dayTimeline
                } else {
                    weekTimeline
                }
            }
            .background(Palette.surfaceSunken)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { shiftDay(mode == .day ? -1 : -7) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Zurück")
                        .accessibilityIdentifier("nav.previous")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { shiftDay(mode == .day ? 1 : 7) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Weiter")
                        .accessibilityIdentifier("nav.next")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { showMembers = true } label: {
                        Label("Familie", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("toolbar.family")
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button { showSearch = true } label: {
                        Label("Suche", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("toolbar.search")
                }
                if canEdit {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Menu {
                            Button { editorTarget = .new } label: {
                                Label("Neuer Termin", systemImage: "calendar.badge.plus")
                            }
                            Button { showPhotoPicker = true } label: {
                                Label("Termine aus Foto", systemImage: "doc.text.viewfinder")
                            }
                            if !pendingSuggestions.isEmpty {
                                Button { showSuggestions = true } label: {
                                    Label("Offene Vorschläge (\(pendingSuggestions.count))", systemImage: "tray")
                                }
                            }
                        } label: {
                            Label("Neu", systemImage: "plus")
                        } primaryAction: {
                            editorTarget = .new
                        }
                        .accessibilityIdentifier("toolbar.new")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                if let household, let me {
                    EventEditorSheet(household: household,
                                     author: me,
                                     event: target.event,
                                     initialDay: day)
                }
            }
            .onChange(of: day, initial: true) { _, new in
                dayEvents.nsPredicate = EventService.eventsRequest(on: new).predicate
                let start = Self.weekStart(of: new)
                let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
                weekEvents.nsPredicate = EventService.eventsRequest(from: start, to: end).predicate
            }
            .sheet(isPresented: $showSearch) {
                SearchScreen(viewer: viewer, household: household) { target in
                    day = target
                    mode = .day
                }
            }
            .sheet(isPresented: $showMembers) {
                if let household {
                    MembersScreen(household: household)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photoImport = PhotoImport(data: data)
                    }
                    photoItem = nil
                }
            }
            .sheet(item: $photoImport) { photo in
                if let household, let me {
                    PhotoImportSheet(imageData: photo.data, household: household, me: me)
                }
            }
            .sheet(isPresented: $showSuggestions) {
                if let me { PendingSuggestionsScreen(me: me) }
            }
            .sheet(isPresented: $showResponsibilities) {
                ResponsibilitiesSheet(me: me)
            }
            .sheet(item: $detailEvent) { event in
                EventDetailSheet(event: event, viewer: viewer, household: household)
            }
            .task(id: day) { await reloadResponsibilities() }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
                scheduleReminders()
            }
            .onReceive(NotificationCenter.default.publisher(for: .remindersNeedReschedule)) { _ in
                scheduleReminders()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDayFromReminder)) { note in
                if let target = note.userInfo?["day"] as? Date {
                    day = target
                    mode = .day
                }
            }
            .task {
                scheduleReminders()
                syncCalendars()
                DeviceRegistrationService.refresh(memberID: me?.id, in: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    syncCalendars()
                    scheduleReminders()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                syncCalendars()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                            object: context)) { _ in
                Task { await reloadResponsibilities() }
            }
        }
    }

    private var dayTimeline: some View {
        DayTimelineView(day: day,
                        members: visibleMembers,
                        events: dayEvents.filter { !$0.isAllDay },
                        zoom: $zoom,
                        viewer: viewer,
                        household: household,
                        onSelect: { event in open(event) },
                        onShowDetails: { event in detailEvent = event },
                        onMove: { event, delta in move(event, by: delta) },
                        canMove: { event in
                            canEdit && EventOrigin(rawValue: event.originRaw ?? "") != .imported
                        },
                        onSwipeDay: { offset in shiftDay(offset) })
    }

    private var weekTimeline: some View {
        WeekTimelineView(weekStart: Self.weekStart(of: day),
                         events: weekEvents.filter { !$0.isAllDay && isVisibleInFilter($0) },
                         zoom: $zoom,
                         viewer: viewer,
                         household: household,
                         onSelect: { event in open(event) },
                         onShowDetails: { event in detailEvent = event },
                         onOpenDay: { target in
                             day = target
                             mode = .day
                         },
                         onSwipeWeek: { offset in shiftDay(offset * 7) },
                         onMove: { event, days, minutes in move(event, days: days, minutes: minutes) },
                         canMove: { event in
                             canEdit && EventOrigin(rawValue: event.originRaw ?? "") != .imported
                         })
    }

    /// Personenfilter gilt auch in der Woche: Termine mit mindestens einer gewählten Person.
    private func isVisibleInFilter(_ event: CDEvent) -> Bool {
        guard !selectedMemberIDs.isEmpty else { return true }
        let participants = ((event.participations as? Set<CDEventParticipation>) ?? [])
            .compactMap { $0.member?.objectID }
        return participants.contains { selectedMemberIDs.contains($0) }
    }

    /// Montag der Woche (Haushalt: Woche beginnt am Montag).
    static func weekStart(of date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? Calendar.current.startOfDay(for: date)
    }

    private var visibleMembers: [CDMember] {
        selectedMemberIDs.isEmpty
            ? Array(members)
            : members.filter { selectedMemberIDs.contains($0.objectID) }
    }

    /// Das Mitglied, das dieses Gerät benutzt.
    private var me: CDMember? {
        _ = currentMemberID
        guard let household else { return nil }
        return CurrentMember.resolve(in: context, household: household)
    }

    /// Termine anlegen und ändern dürfen nur Erwachsene.
    private var canEdit: Bool { previewMember == nil && me?.role == .adult }

    /// Kind, dessen Sicht ein Erwachsener gerade als Vorschau ansieht.
    private var previewMember: CDMember? {
        guard let raw = previewMemberID, let id = UUID(uuidString: raw), me?.role == .adult,
              let household else { return nil }
        return ((household.members as? Set<CDMember>) ?? []).first { $0.id == id && $0.isActive }
    }

    /// Aus wessen Sicht Titel und Orte gezeigt werden.
    private var viewer: CDMember? { previewMember ?? me }

    private var title: String {
        if mode == .week {
            let start = Self.weekStart(of: day)
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = .current
            let week = iso.component(.weekOfYear, from: start)
            // Kurz, damit der Titel zwischen die Pfeile passt: "KW 39 · 21.–27.9."
            let cal = Calendar.current
            let d1 = cal.component(.day, from: start), m1 = cal.component(.month, from: start)
            let d2 = cal.component(.day, from: end), m2 = cal.component(.month, from: end)
            return m1 == m2 ? "KW \(week) · \(d1).–\(d2).\(m2)." : "KW \(week) · \(d1).\(m1).–\(d2).\(m2)."
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = Calendar.current.isDateInToday(day) ? "'Heute', d. MMMM" : "EEEE, d. MMMM"
        return formatter.string(from: day)
    }

    private func shiftDay(_ offset: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            day = Calendar.current.date(byAdding: .day, value: offset, to: day) ?? day
        }
    }

    /// Verschieben per Ziehen: Dauer bleibt, Beginn und Ende wandern gemeinsam.
    private func move(_ event: CDEvent, by delta: TimeInterval) {
        move(event, days: 0, minutes: Int(delta / 60))
    }

    /// Antippen: Eigene Termine bearbeiten Erwachsene im Editor. Übernommene Kalendertermine
    /// und alles für Kinder bzw. in der Vorschau zeigt die Detailansicht mit genauen Zeiten.
    private func open(_ event: CDEvent) {
        if canEdit, EventOrigin(rawValue: event.originRaw ?? "") != .imported {
            editorTarget = .existing(event)
        } else {
            detailEvent = event
        }
    }

    /// Verschieben um ganze Tage (kalendarisch, sommerzeitsicher) und Minuten.
    private func move(_ event: CDEvent, days: Int, minutes: Int) {
        guard let start = event.startAt, let end = event.endAt else { return }
        let calendar = Calendar.current
        let duration = end.timeIntervalSince(start)
        let shifted = calendar.date(byAdding: .day, value: days, to: start) ?? start
        let newStart = shifted.addingTimeInterval(TimeInterval(minutes * 60))
        event.startAt = newStart
        event.endAt = newStart.addingTimeInterval(duration)
        event.updatedAt = Date()
        PersistenceController.shared.save(context)
    }

    /// Erinnerungen neu planen, gebündelt: mehrere Speichervorgänge kurz hintereinander
    /// lösen nur eine Neuberechnung aus.
    private func scheduleReminders() {
        reminderTask?.cancel()
        reminderTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await ReminderService.reschedule(me: me, household: household, in: context)
        }
    }

    /// Kalender dieses Geräts abgleichen (nur, wenn Zugriff erteilt und Kalender gewählt).
    private func syncCalendars() {
        guard let household, let me else { return }
        CalendarImportService.shared.sync(household: household, member: me, in: context)
    }

    private func reloadResponsibilities() async {
        openResponsibilities = (try? EventService.openResponsibilities(in: context)) ?? []
    }
}

// MARK: - Stapel offener Zuständigkeiten

struct OpenResponsibilityBanner: View {
    let items: [OpenResponsibility]

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(Palette.color("person5"))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(items.count) offene \(items.count == 1 ? "Zuständigkeit" : "Zuständigkeiten")")
                    .font(.system(size: 14, weight: .semibold))
                Text(items.prefix(2).map { "\($0.role.label): \($0.eventTitle)" }.joined(separator: " · "))
                    .font(TypeScale.eventMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }
}

// MARK: - Ziel des Editors

enum EditorTarget: Identifiable {
    case new
    case existing(CDEvent)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let event): return event.objectID.uriRepresentation().absoluteString
        }
    }

    var event: CDEvent? {
        if case .existing(let event) = self { return event }
        return nil
    }
}

/// Ein ausgewähltes Foto, das eingelesen werden soll.
struct PhotoImport: Identifiable {
    let id = UUID()
    let data: Data
}

enum CalendarMode: Hashable {
    case day, week
}
