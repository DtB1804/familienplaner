import SwiftUI
import CoreData
import EventKit

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
    @State private var zoom: DayZoom = .normal
    @State private var selectedMemberIDs: Set<NSManagedObjectID> = []
    @State private var openResponsibilities: [OpenResponsibility] = []
    @State private var showMembers = false
    @State private var editorTarget: EditorTarget?
    @State private var showResponsibilities = false
    @State private var importedNotice = false

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
                dayTimeline
            }
            .background(Palette.surfaceSunken)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { showMembers = true } label: {
                        Label("Familie", systemImage: "person.2")
                    }
                }
                if canEdit {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button { editorTarget = .new } label: {
                            Label("Neuer Termin", systemImage: "plus")
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
            }
            .sheet(isPresented: $showMembers) {
                if let household {
                    MembersScreen(household: household)
                }
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
            .task { syncCalendars() }
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
