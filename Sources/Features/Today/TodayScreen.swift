import SwiftUI
import CoreData
import EventKit
import PhotosUI
import UIKit

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

    /// Startwert gleich die richtige Woche: Ein nachträglich gesetztes `nsPredicate`
    /// greift beim ersten Anzeigen nicht zuverlässig (Woche und Monat blieben leer).
    @FetchRequest(fetchRequest: TodayScreen.weekRequest(for: Date()))
    private var weekEvents: FetchedResults<CDEvent>
    /// Sechs Wochen der Monatsübersicht.
    @FetchRequest(fetchRequest: TodayScreen.monthRequest(for: Date()))
    private var monthEvents: FetchedResults<CDEvent>
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
    @State private var showFreeTime = false
    @State private var showCamera = false
    @State private var cameraData: Data?
    @State private var showDatePicker = false
    @State private var pasteEmpty = false
    /// "Bearbeiten" in der Detailansicht: nach dem Schließen den Editor öffnen.
    @State private var pendingEdit: CDEvent?
    /// Letzte Verschiebung per Ziehen, einige Sekunden lang rückgängig zu machen.
    @State private var undo: UndoAction?
    @ObservedObject private var syncStatus = SyncStatus.shared

    @FetchRequest(fetchRequest: SuggestionService.pendingRequest())
    private var pendingSuggestions: FetchedResults<CDSuggestionDraft>

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let problem = syncStatus.problem {
                    SyncBanner(problem: problem, lastSuccess: syncStatus.lastSuccess)
                }
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
                headerBar
                banners
                let allDay = (mode == .day ? Array(dayEvents) : Array(weekEvents))
                    .filter { $0.isAllDay && isVisibleInFilter($0) }
                if mode != .month && !allDay.isEmpty {
                    AllDayStrip(events: allDay, showsDates: mode == .week,
                                viewer: viewer, household: household,
                                onSelect: { event in open(event) })
                }
                switch mode {
                case .day: dayTimeline
                case .week: weekTimeline
                case .month: monthGrid
                }
            }
            .background(Palette.surfaceSunken)
            .overlay(alignment: .bottom) {
                if let undo {
                    UndoToast(text: undo.text) {
                        undo.revert()
                        self.undo = nil
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: undo?.id)
            .task(id: undo?.id) {
                guard undo != nil else { return }
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled { undo = nil }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
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
                weekEvents.nsPredicate = Self.weekRequest(for: new).predicate
                monthEvents.nsPredicate = Self.monthRequest(for: new).predicate
            }
            .alert("Nichts kopiert", isPresented: $pasteEmpty) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Kopiere zuerst den Text mit dem Termin, z. B. eine WhatsApp-Nachricht: lange drücken → Kopieren.")
            }
            .sheet(isPresented: $showDatePicker) {
                DayPickerSheet(day: Binding(get: { day }, set: { new in
                    withAnimation(.snappy(duration: 0.2)) { day = new }
                    showDatePicker = false
                }))
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
                        photoImport = PhotoImport(source: .image(data))
                    }
                    photoItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                // Erst nach dem Schließen der Kamera das Prüfblatt zeigen.
                if let data = cameraData { photoImport = PhotoImport(source: .image(data)) }
                cameraData = nil
            }) {
                CameraPicker { data in cameraData = data }
                    .ignoresSafeArea()
            }
            .sheet(item: $photoImport, onDismiss: takeSharedPhoto) { photo in
                if let household, let me {
                    PhotoImportSheet(source: photo.source, household: household, me: me)
                }
            }
            .sheet(isPresented: $showSuggestions) {
                if let me { PendingSuggestionsScreen(me: me) }
            }
            .sheet(isPresented: $showFreeTime) {
                if let household, let me {
                    FreeTimeScreen(household: household, author: me)
                }
            }
            .sheet(isPresented: $showResponsibilities) {
                ResponsibilitiesSheet(me: me)
            }
            .sheet(item: $detailEvent, onDismiss: {
                if let event = pendingEdit {
                    pendingEdit = nil
                    editorTarget = .existing(event)
                }
            }) { event in
                EventDetailSheet(event: event, viewer: viewer, household: household,
                                 onEdit: isEditable(event) ? {
                                     pendingEdit = event
                                     detailEvent = nil
                                 } : nil)
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
                takeSharedPhoto()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    syncCalendars()
                    scheduleReminders()
                    takeSharedPhoto()
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



    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Zurück")
                .accessibilityIdentifier("nav.previous")
        }
        ToolbarItem(placement: .principal) {
            Button { showDatePicker = true } label: {
                HStack(spacing: 4) {
                    Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .frame(minHeight: 44)          // Trefferfläche (Barrierefreiheitsprüfung)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(mode == .day
                ? day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE")))
                : title)
            .accessibilityHint("Datum wählen")
            .accessibilityIdentifier("nav.title")
        }
        if !isShowingToday {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Heute") { withAnimation(.snappy(duration: 0.2)) { day = Date() } }
                    .accessibilityIdentifier("nav.today")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { step(1) } label: { Image(systemName: "chevron.right") }
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
                Button { showFreeTime = true } label: {
                    Label("Freie Zeit", systemImage: "calendar.badge.clock")
                }
                .accessibilityIdentifier("toolbar.free")
            }
        }
        if canEdit {
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                // Eigener Knopf statt verstecktem Menü hinter "+" (UX-Prüfung A3).
                Menu {
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            Label("Termine fotografieren", systemImage: "camera")
                        }
                    }
                    Button { showPhotoPicker = true } label: {
                        Label("Foto oder Bildschirmfoto auswählen", systemImage: "photo.on.rectangle")
                    }
                    Button { pasteText() } label: {
                        Label("Kopierten Text einfügen", systemImage: "doc.on.clipboard")
                    }
                    if !pendingSuggestions.isEmpty {
                        Button { showSuggestions = true } label: {
                            Label("Offene Vorschläge (\(pendingSuggestions.count))", systemImage: "tray")
                        }
                    }
                } label: {
                    Label("Foto oder Text", systemImage: "camera")
                }
                .accessibilityHint("Termine aus einem Elternbrief, Aushang oder kopierten Text erkennen")
                .accessibilityIdentifier("toolbar.photo")
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button { editorTarget = .new } label: {
                    Label("Neu", systemImage: "plus")
                }
                .accessibilityIdentifier("toolbar.new")
            }
        }
    }

    // MARK: - Kopfbereich (ausgelagert, damit die Typprüfung schnell bleibt)

    private var headerBar: some View {
        // Eine Leiste für Personen, Tag/Woche und Zoom (UX-Prüfung B5).
        HStack(spacing: Spacing.s) {
            MemberFilterBar(members: Array(members), selection: $selectedMemberIDs)
            // Tag/Woche und Zoom in einem Menü, damit die Namen die Zeile nutzen können
            // (vier Personen sollen nebeneinander passen).
            Menu {
                Picker("Ansicht", selection: $mode) {
                    Label("Tag", systemImage: "calendar.day.timeline.left").tag(CalendarMode.day)
                    Label("Woche", systemImage: "rectangle.split.3x1").tag(CalendarMode.week)
                    Label("Monat", systemImage: "calendar").tag(CalendarMode.month)
                }
                Section {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { zoom = zoom.zoomedIn() }
                    } label: {
                        Label("Vergrößern", systemImage: "plus.magnifyingglass")
                    }
                    .disabled(!zoom.canZoomIn)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { zoom = zoom.zoomedOut() }
                    } label: {
                        Label("Verkleinern", systemImage: "minus.magnifyingglass")
                    }
                    .disabled(!zoom.canZoomOut)
                }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: mode.symbol)
                        .font(.body.weight(.semibold))
                    Text(mode.label)
                        .font(.caption2.weight(.medium))
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Ansicht: \(mode.label)")
            .accessibilityHint("Tag, Woche oder Monat wählen, vergrößern oder verkleinern")
            .accessibilityIdentifier("view.menu")
            .padding(.trailing, Spacing.s)
        }
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var banners: some View {
        if canEdit && !openResponsibilities.isEmpty {
            Button { showResponsibilities = true } label: {
                OpenResponsibilityBanner(items: openResponsibilities)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("banner.open")
        }
        if canEdit && !pendingSuggestions.isEmpty {
            Button { showSuggestions = true } label: {
                HintBanner(symbol: "doc.text.viewfinder",
                           title: pendingSuggestions.count == 1
                               ? "1 Foto wartet auf Prüfung"
                               : "\(pendingSuggestions.count) Fotos warten auf Prüfung",
                           detail: "Erkannte Termine ansehen und eintragen")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("banner.suggestions")
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
                        onSwipeDay: { offset in shiftDay(offset) },
                        onReassign: canEdit ? { event, from, to in
                            guard EventOrigin(rawValue: event.originRaw ?? "") != .imported else { return }
                            reassign(event, from: from, to: to)
                        } : nil)
    }

    private var monthGrid: some View {
        MonthGridView(month: day,
                      events: monthEvents.filter { isVisibleInFilter($0) },
                      members: visibleMembers,
                      viewer: viewer,
                      household: household,
                      onOpenDay: { target in
                          day = target
                          mode = .day
                      },
                      onSwipeMonth: { offset in shiftMonth(offset) })
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
        if mode == .month {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: day)
        }
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
        // Ist nicht heute gewählt, steht rechts zusätzlich "Heute": dann kurze Form,
        // sonst wird der Titel abgeschnitten ("…nstag, 29. September").
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        let cal = Calendar.current
        if cal.isDateInToday(day) {
            formatter.dateFormat = "'Heute', d. MMMM"
        } else if cal.isDateInTomorrow(day) {
            formatter.dateFormat = "'Morgen', d. MMM"
        } else if cal.isDateInYesterday(day) {
            formatter.dateFormat = "'Gestern', d. MMM"
        } else {
            formatter.dateFormat = "EEE, d. MMM"
        }
        return formatter.string(from: day)
    }

    /// Pfeile: je nach Ansicht einen Tag, eine Woche oder einen Monat weiter.
    private func step(_ direction: Int) {
        switch mode {
        case .day: shiftDay(direction)
        case .week: shiftDay(direction * 7)
        case .month: shiftMonth(direction)
        }
    }

    private func shiftMonth(_ offset: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            day = Calendar.current.date(byAdding: .month, value: offset, to: day) ?? day
        }
    }

    /// Die 42 Tage der Monatsübersicht (Montag vor dem Monatsersten, sechs Wochen).
    static func weekRequest(for date: Date) -> NSFetchRequest<CDEvent> {
        let start = weekStart(of: date)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return EventService.eventsRequest(from: start, to: end)
    }

    static func monthRequest(for date: Date) -> NSFetchRequest<CDEvent> {
        let grid = monthGridRange(of: date)
        return EventService.eventsRequest(from: grid.start, to: grid.end)
    }

    static func monthGridRange(of date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let start = calendar.dateInterval(of: .weekOfYear, for: first)?.start ?? first
        let end = calendar.date(byAdding: .day, value: 42, to: start) ?? start
        return (start, end)
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
    /// Über den Teilen-Knopf (Mail, WhatsApp, Fotos) geschickte Bilder nacheinander prüfen.
    private func takeSharedPhoto() {
        guard canEdit, photoImport == nil, !showCamera else { return }
        switch SharedInbox.takeNextItem() {
        case .image(let data): photoImport = PhotoImport(source: .image(data))
        case .text(let text): photoImport = PhotoImport(source: .text(text))
        case nil: break
        }
    }

    /// Antippen zeigt immer zuerst die Details (wie in der Kalender-App); bearbeitet wird
    /// über "Bearbeiten" oben rechts (UX-Prüfung B4).
    /// Kopierten Text (z. B. aus WhatsApp) auswerten. iOS fragt beim ersten Mal nach.
    private func pasteText() {
        if let text = UIPasteboard.general.string,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            photoImport = PhotoImport(source: .text(String(text.prefix(5000))))
        } else {
            pasteEmpty = true
        }
    }

    private func open(_ event: CDEvent) {
        detailEvent = event
    }

    private func isEditable(_ event: CDEvent) -> Bool {
        canEdit && EventOrigin(rawValue: event.originRaw ?? "") != .imported
    }

    /// Verschieben um ganze Tage (kalendarisch, sommerzeitsicher) und Minuten.
    /// Bei Serien betrifft das nur diesen Termin; der Hinweis sagt das und bietet Rückgängig.
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

        let style: Date.FormatStyle = days == 0
            ? .dateTime.hour().minute().locale(Locale(identifier: "de_DE"))
            : .dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "de_DE"))
        var text = "\(shortTitle(event)) → \(newStart.formatted(style))"
        if SeriesService.isSeries(event) { text += " · nur dieser Termin" }
        undo = UndoAction(text: text) {
            event.startAt = start
            event.endAt = end
            event.updatedAt = Date()
            PersistenceController.shared.save(context)
        }
    }

    /// Seitlich in eine andere Spalte gezogen: Termin betrifft jetzt die andere Person.
    private func reassign(_ event: CDEvent, from: CDMember, to: CDMember) {
        let targetWasSubject = EventService.subjects(of: event).contains { $0.objectID == to.objectID }
        guard EventService.reassignSubject(event, from: from, to: to, in: context) else { return }
        PersistenceController.shared.save(context)
        undo = UndoAction(text: "\(shortTitle(event)) → \(to.displayName ?? "")") {
            if targetWasSubject {
                EventService.addParticipation(in: context, event: event, member: from, role: .subject)
                event.updatedAt = Date()
            } else {
                _ = EventService.reassignSubject(event, from: to, to: from, in: context)
            }
            PersistenceController.shared.save(context)
        }
    }

    private func shortTitle(_ event: CDEvent) -> String {
        let title = EventPresentation.title(of: event, for: viewer, in: household)
        return title.count > 22 ? String(title.prefix(21)) + "…" : title
    }

    /// Zeigt die Ansicht heute (Tag) bzw. die laufende Woche?
    private var isShowingToday: Bool {
        switch mode {
        case .day: return Calendar.current.isDateInToday(day)
        case .week: return Self.weekStart(of: day) == Self.weekStart(of: Date())
        case .month: return Calendar.current.isDate(day, equalTo: Date(), toGranularity: .month)
        }
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
                    .font(.subheadline.weight(.semibold))
                Text(items.prefix(2).map { "\($0.role.label): \($0.eventTitle)" }.joined(separator: " · "))
                    .font(TypeScale.eventMeta)
                    .foregroundStyle(.secondary)
                    // Bei großer Schrift umbrechen statt abschneiden (Barrierefreiheitsprüfung 02.10.).
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
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
    let source: ImportSource
}

enum CalendarMode: Hashable {
    case day, week, month

    var label: String {
        switch self {
        case .day: return "Tag"
        case .week: return "Woche"
        case .month: return "Monat"
        }
    }

    var symbol: String {
        switch self {
        case .day: return "calendar.day.timeline.left"
        case .week: return "rectangle.split.3x1"
        case .month: return "calendar"
        }
    }
}

// MARK: - Rückgängig nach dem Ziehen

struct UndoAction: Identifiable {
    let id = UUID()
    let text: String
    let revert: () -> Void
}

struct UndoToast: View {
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(text)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: Spacing.s)
            Button("Rückgängig", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("undo.button")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("undo.toast")
    }
}

// MARK: - Hinweisleiste (z. B. Foto-Vorschläge)

struct HintBanner: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(TypeScale.eventMeta).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Datum wählen

struct DayPickerSheet: View {
    @Binding var day: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Datum", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "de_DE"))
                    .padding(.horizontal)
                    .accessibilityIdentifier("datepicker")
                Spacer(minLength: 0)
            }
            .navigationTitle("Datum wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Heute") { day = Date() }
                        .accessibilityIdentifier("datepicker.today")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
