import SwiftUI
import CoreData

/// "Wann haben alle frei?" Auswahl der Personen, Dauer und Tageszeit; Tippen auf eine
/// freie Zeit legt dort einen Termin für diese Personen an.
struct FreeTimeScreen: View {

    let household: CDHousehold
    let author: CDMember

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(fetchRequest: HouseholdService.activeMembersRequest())
    private var members: FetchedResults<CDMember>

    @State private var selected: Set<NSManagedObjectID> = []
    @State private var didLoad = false
    @State private var minutes = 60
    @State private var dayPart: FreeTimeFinder.DayPart = .wholeDay
    @State private var days: FreeTimeFinder.Days = .all
    @State private var range = 14
    @State private var slots: [FreeTimeFinder.Interval] = []
    @State private var newEvent: FreeTimeFinder.Interval?

    private let durations = [30, 60, 90, 120, 180, 240, 360]
    private let de = Locale(identifier: "de_DE")

    var body: some View {
        NavigationStack {
            Form {
                Section("Wer") {
                    ForEach(members, id: \.objectID) { member in
                        Button { toggle(member) } label: {
                            HStack {
                                Circle().fill(Palette.color(member.colorToken ?? "person1")).frame(width: 10, height: 10)
                                Text(member.displayName ?? "").foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(member.objectID) {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("free.member.\(member.displayName ?? "")")
                    }
                }

                Section("Was") {
                    Picker("Mindestens", selection: $minutes) {
                        ForEach(durations, id: \.self) { Text(Self.durationText(TimeInterval($0 * 60))).tag($0) }
                    }
                    Picker("Tageszeit", selection: $dayPart) {
                        ForEach(FreeTimeFinder.DayPart.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Tage", selection: $days) {
                        ForEach(FreeTimeFinder.Days.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Zeitraum", selection: $range) {
                        Text("1 Woche").tag(7)
                        Text("2 Wochen").tag(14)
                        Text("4 Wochen").tag(28)
                    }
                }

                if selected.isEmpty {
                    Section { Text("Mindestens eine Person auswählen.").foregroundStyle(.secondary) }
                } else if slots.isEmpty {
                    Section { Text("Keine gemeinsame freie Zeit gefunden.").foregroundStyle(.secondary) }
                } else {
                    ForEach(groupedSlots, id: \.0) { day, items in
                        Section(dayTitle(day)) {
                            ForEach(items, id: \.self) { slot in
                                Button { newEvent = slot } label: {
                                    HStack {
                                        Text("\(time(slot.start))–\(time(slot.end))")
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(Self.durationText(slot.duration))
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "plus.circle").foregroundStyle(.blue)
                                    }
                                }
                                .accessibilityIdentifier("free.slot.\(Self.dayKey(slot.start)).\(time(slot.start))")
                            }
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Belegt sind Termine der Personen und übernommene Zuständigkeiten (Bringen, Holen, Begleiten). Ganztägige Termine wie Urlaub oder Geburtstag zählen nicht, ganztägige Dienste schon. Tippen auf eine Zeit legt dort einen Termin an.")
                }
            }
            .navigationTitle("Freie Zeit finden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("free.done")
                }
            }
            .onAppear {
                if !didLoad {
                    didLoad = true
                    selected = Set(members.map(\.objectID))
                }
                recompute()
            }
            .onChange(of: selected) { _, _ in recompute() }
            .onChange(of: minutes) { _, _ in recompute() }
            .onChange(of: dayPart) { _, _ in recompute() }
            .onChange(of: days) { _, _ in recompute() }
            .onChange(of: range) { _, _ in recompute() }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                            object: context)) { _ in recompute() }
            .sheet(item: $newEvent) { slot in
                EventEditorSheet(household: household, author: author, event: nil,
                                 initialDay: slot.start,
                                 initialStart: slot.start,
                                 initialEnd: slot.start.addingTimeInterval(min(TimeInterval(minutes * 60), slot.duration)),
                                 initialSubjectIDs: selected)
            }
        }
    }

    // MARK: - Berechnung

    private func recompute() {
        let chosen = members.filter { selected.contains($0.objectID) }
        guard !chosen.isEmpty else { slots = []; return }
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: range + 1, to: start) ?? start
        let events = (try? context.fetch(EventService.eventsRequest(from: start, to: end))) ?? []
        let busy = FreeTimeFinder.busyIntervals(events: events, members: Array(chosen))
        slots = FreeTimeFinder.freeSlots(busy: busy, now: now, days: range, dayPart: dayPart,
                                         filter: days, minimum: TimeInterval(minutes * 60))
    }

    private func toggle(_ member: CDMember) {
        if selected.contains(member.objectID) { selected.remove(member.objectID) } else { selected.insert(member.objectID) }
    }

    private var groupedSlots: [(Date, [FreeTimeFinder.Interval])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: slots) { calendar.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { ($0, groups[$0]!) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let text = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(de))
        if calendar.isDateInToday(day) { return "Heute, " + text }
        if calendar.isDateInTomorrow(day) { return "Morgen, " + text }
        return text
    }

    private func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(de))
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) Min."
        case (_, 0): return "\(hours) Std."
        case (_, 30): return "\(hours),5 Std."
        default: return "\(hours) Std. \(rest) Min."
        }
    }
}

extension FreeTimeFinder.Interval: Identifiable {
    var id: Date { start }
}
