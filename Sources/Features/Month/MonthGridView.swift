import SwiftUI
import CoreData

/// Monatsübersicht: sechs Wochen, Montag bis Sonntag. Pro Tag ein Punkt je Person mit
/// Terminen, ganztägige Termine (Urlaub, Ferien) als Balken oben in der Zelle; aufeinander
/// folgende Tage ergeben so einen durchgehenden Streifen. Tippen öffnet den Tag.
struct MonthGridView: View {

    let month: Date
    let events: [CDEvent]
    let members: [CDMember]
    var viewer: CDMember? = nil
    var household: CDHousehold? = nil
    let onOpenDay: (Date) -> Void
    /// Wischen nach links (+1) oder rechts (−1) blättert den Monat.
    var onSwipeMonth: ((Int) -> Void)? = nil

    private let de = Locale(identifier: "de_DE")
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        calendar.locale = de
        return calendar
    }

    /// Erster Tag des Monats.
    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: month)?.start ?? calendar.startOfDay(for: month)
    }

    /// 42 Tage ab dem Montag vor (oder am) Monatsersten.
    private var days: [Date] {
        let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        dayCell(day)
                    }
                }
                .padding(.bottom, 110)   // Platz unter der schwebenden Werkzeugleiste
            }
        }
        .background(Palette.surfaceSunken)
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                onSwipeMonth?(dx < 0 ? 1 : -1)
            })
        .accessibilityIdentifier("month.grid")
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Spacing.xs)
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Zelle

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: monthStart, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let dayEvents = events(on: day)
        let allDay = dayEvents.filter(\.isAllDay)
        let people = membersWithEvents(dayEvents)

        return Button { onOpenDay(day) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary))
                    .frame(width: 26, height: 26)
                    .background(isToday ? Color.accentColor : Color.clear, in: Circle())
                ForEach(allDay.prefix(2), id: \.objectID) { event in
                    allDayBar(event)
                }
                HStack(spacing: 3) {
                    ForEach(people.prefix(5), id: \.objectID) { member in
                        Circle()
                            .fill(Palette.color(member.colorToken ?? "person1"))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(inMonth ? Palette.surface : Palette.surfaceSunken)
            .overlay {
                Rectangle().stroke(Palette.hairline, lineWidth: 0.5)
            }
            .opacity(inMonth ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel(day, events: dayEvents))
        .accessibilityHint("Öffnet den Tag")
        .accessibilityIdentifier("month.day.\(Self.dayKey(day))")
    }

    private func allDayBar(_ event: CDEvent) -> some View {
        let subject = EventService.subjects(of: event).first
        let busy = EventPresentation.isBusyOnly(event, for: viewer, in: household)
        let tint = busy ? Palette.busy : Palette.color(subject?.colorToken ?? "person1")
        return Text(EventPresentation.title(of: event, for: viewer, in: household))
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Hilfsrechnungen

    /// Termine, die diesen Tag berühren (Ende exklusiv, wie bei ganztägigen Terminen).
    private func events(on day: Date) -> [CDEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { event in
            guard let from = event.startAt, let to = event.endAt else { return false }
            return from < end && to > start
        }
    }

    /// Personen (in Reihenfolge der Familie), die an diesem Tag etwas haben.
    private func membersWithEvents(_ dayEvents: [CDEvent]) -> [CDMember] {
        let ids = Set(dayEvents.flatMap { event in
            ((event.participations as? Set<CDEventParticipation>) ?? []).compactMap { $0.member?.objectID }
        })
        return members.filter { ids.contains($0.objectID) }
    }

    private func spokenLabel(_ day: Date, events: [CDEvent]) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(de))
        guard !events.isEmpty else { return "\(date), keine Termine" }
        let titles = events.prefix(3).map { EventPresentation.title(of: $0, for: viewer, in: household) }
        let count = events.count == 1 ? "1 Termin" : "\(events.count) Termine"
        return "\(date), \(count): " + titles.joined(separator: ", ")
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
