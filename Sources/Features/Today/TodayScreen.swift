import SwiftUI
import CoreData

public struct TodayScreen: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.household) private var household

    @FetchRequest(fetchRequest: HouseholdService.activeMembersRequest())
    private var members: FetchedResults<CDMember>

    @State private var day = Date()
    @State private var zoom: DayZoom = .normal
    @State private var selectedMemberIDs: Set<NSManagedObjectID> = []
    @State private var openResponsibilities: [OpenResponsibility] = []
    @State private var showMembers = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MemberFilterBar(members: Array(members), selection: $selectedMemberIDs)
                if !openResponsibilities.isEmpty {
                    OpenResponsibilityBanner(items: openResponsibilities)
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
            }
            .sheet(isPresented: $showMembers) {
                if let household {
                    MembersScreen(household: household)
                }
            }
            .task(id: day) { await reloadResponsibilities() }
        }
    }

    private var dayTimeline: some View {
        DayTimelineView(day: day,
                        members: visibleMembers,
                        events: eventsOfDay,
                        zoom: $zoom)
    }

    private var visibleMembers: [CDMember] {
        selectedMemberIDs.isEmpty
            ? Array(members)
            : members.filter { selectedMemberIDs.contains($0.objectID) }
    }

    /// Bewusst ein direkter Fetch statt eines zweiten @FetchRequest:
    /// Der Tag wechselt, und ein @FetchRequest mit veränderlichem Prädikat
    /// erzeugt in SwiftUI mehr Sonderfälle als er spart.
    private var eventsOfDay: [CDEvent] {
        (try? context.fetch(EventService.eventsRequest(on: day))) ?? []
    }

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
