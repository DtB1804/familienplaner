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

    @State private var day = Date()
    @State private var mode: CalendarMode = .day
    @State private var showSearch = false

    @FetchRequest(fetchRequest: EventService.eventsRequest(from: Date(), to: Date()))
    private var weekEvents: FetchedResults<CDEvent>
    @State private var zoom: DayZoom = .normal
    @State private var selectedMemberIDs: Set<NSManagedObjectID> = []
    @State private var openResponsibilities: [OpenResponsibility] = []
    @State private var showMembers = false
    @State private var editorTarget: EditorTarget?
    @State private var showResponsibilities = false
    @State private var importedNotice = false
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
                MemberFilterBar(members: Array(members), selection: $selectedMemberIDs)
                if !openResponsibilities.isEmpty {
                    Button { showResponsibilities = true } label: {
                        OpenResponsibilityBanner(items: openResponsibilities)
                    }
                    .buttonStyle(.plain)
                }
                Picker("Ansicht", selection: $mode) {
                    Text("Tag").tag(CalendarMode.day)
                    Text("Woche").tag(CalendarMode.week)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .background(Palette.surface)
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { shiftDay(mode == .day ? 1 : 7) } label: { Image(systemName: "chevron.right") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { showMembers = true } label: {
                        Label("Familie", systemImage: "person.2")
                    }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button { showSearch = true } label: {
                        Label("Suche", systemImage: "magnifyingglass")
                    }
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
                SearchScreen(viewer: me, household: household) { target in
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
            .alert("Aus Ihrem Kalender übernommen",
                   isPresented: $importedNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Diesen Termin ändern Sie in der Kalender-App. Die Änderung kommt automatisch hierher.")
            }
            .task(id: day) { await reloadResponsibilities() }
            .task {
                syncCalendars()
                DeviceRegistrationService.refresh(memberID: me?.id, in: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { syncCalendars() }
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
                        events: Array(dayEvents),
                        zoom: $zoom,
                        viewer: me,
                        household: household,
                        onSelect: { event in
                            guard canEdit else { return }
                            if EventOrigin(rawValue: event.originRaw ?? "") == .imported {
                                importedNotice = true
                            } else {
                                editorTarget = .existing(event)
                            }
                        },
                        onMove: { event, delta in move(event, by: delta) },
                        canMove: { event in
                            canEdit && EventOrigin(rawValue: event.originRaw ?? "") != .imported
                        },
                        onSwipeDay: { offset in shiftDay(offset) })
    }

    private var weekTimeline: some View {
        WeekTimelineView(weekStart: Self.weekStart(of: day),
                         events: weekEvents.filter(isVisibleInFilter),
                         zoom: $zoom,
                         viewer: me,
                         household: household,
                         onSelect: { event in
                             if canEdit, EventOrigin(rawValue: event.originRaw ?? "") != .imported {
                                 editorTarget = .existing(event)
                             } else if let start = event.startAt {
                                 day = start
                                 mode = .day
                             }
                         },
                         onOpenDay: { target in
                             day = target
                             mode = .day
                         },
                         onSwipeWeek: { offset in shiftDay(offset * 7) })
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
    private var canEdit: Bool { me?.role == .adult }

    private var title: String {
        if mode == .week {
            let start = Self.weekStart(of: day)
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = .current
            let week = iso.component(.weekOfYear, from: start)
            let de = Locale(identifier: "de_DE")
            return "KW \(week) · \(start.formatted(.dateTime.day().month(.abbreviated).locale(de))) – \(end.formatted(.dateTime.day().month(.abbreviated).locale(de)))"
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
        guard let start = event.startAt, let end = event.endAt else { return }
        event.startAt = start.addingTimeInterval(delta)
        event.endAt = end.addingTimeInterval(delta)
        event.updatedAt = Date()
        PersistenceController.shared.save(context)
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
