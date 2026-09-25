import SwiftUI
import CoreData

/// Wochenansicht: sieben Tagesspalten (Montag bis Sonntag) auf einem Zeitstrahl.
///
/// Die Farbe eines Termins ist die Farbe der ersten betroffenen Person, "Belegt" ist grau.
/// Tippen auf den Tageskopf öffnet die Tagesansicht mit den Personenspalten.
struct WeekTimelineView: View {

    let weekStart: Date
    let events: [CDEvent]
    @Binding var zoom: DayZoom
    var viewer: CDMember?
    var household: CDHousehold?
    var onSelect: (CDEvent) -> Void
    var onShowDetails: (CDEvent) -> Void = { _ in }
    var onOpenDay: (Date) -> Void
    var onSwipeWeek: (Int) -> Void
    /// Verschieben per Gedrückthalten und Ziehen: ganze Tage (seitlich) und Minuten (vertikal).
    var onMove: (CDEvent, Int, Int) -> Void = { _, _, _ in }
    var canMove: (CDEvent) -> Bool = { _ in false }

    @State private var draggingID: NSManagedObjectID?
    @State private var dragOffset: CGSize = .zero
    @State private var lastDragEnd = Date.distantPast
    private let snapMinutes = 15

    private let gutterWidth: CGFloat = 36
    private let startHour = 6
    private let endHour = 23

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = (geometry.size.width - gutterWidth) / 7
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    grid(columnWidth: columnWidth)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        dayHeaders(columnWidth: columnWidth)
                        Rectangle().fill(Palette.hairline).frame(height: 0.5)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .simultaneousGesture(swipe)
                .onAppear { proxy.scrollTo(7, anchor: .top) }
            }
        }
        .background(Palette.surfaceSunken)
        .gesture(MagnifyGesture().onEnded { value in
            withAnimation(.snappy(duration: 0.22)) {
                zoom = value.magnification > 1 ? zoom.zoomedIn() : zoom.zoomedOut()
            }
        })
    }

    // MARK: - Kopf

    private func dayHeaders(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth)
            ForEach(days, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                Button { onOpenDay(day) } label: {
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE"))))
                            .font(TypeScale.eventMeta)
                            .foregroundStyle(.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(TypeScale.laneHeader)
                            .foregroundStyle(isToday ? Color.white : Color.primary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(isToday ? Palette.color("person1") : .clear))
                    }
                    .frame(width: columnWidth, height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Palette.surface)
    }

    // MARK: - Raster

    private func grid(columnWidth: CGFloat) -> some View {
        let height = CGFloat(endHour - startHour) * zoom.pointsPerHour
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(startHour..<endHour, id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .id(hour)
                        .font(TypeScale.hourLabel)
                        .foregroundStyle(.tertiary)
                        .frame(height: zoom.pointsPerHour, alignment: .top)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, Spacing.xs)
                }
            }
            .frame(width: gutterWidth, height: height, alignment: .top)

            ForEach(days, id: \.self) { day in
                dayColumn(day, width: columnWidth, height: height)
                    // Die Spalte mit dem gezogenen Termin liegt oben, sonst verschwindet er
                    // beim seitlichen Ziehen hinter den Nachbarspalten.
                    .zIndex(eventsOn(day).contains { $0.objectID == draggingID } ? 1 : 0)
            }
        }
        .padding(.bottom, 110)   // Platz unter der schwebenden Werkzeugleiste
    }

    private func dayColumn(_ day: Date, width: CGFloat, height: CGFloat) -> some View {
        let placed = layout(eventsOn(day), day: day)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Calendar.current.isDateInToday(day) ? Palette.surface : Palette.surface.opacity(0.55))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Palette.hairline).frame(width: 0.5)
                }
            VStack(spacing: 0) {
                ForEach(startHour..<endHour, id: \.self) { _ in
                    VStack(spacing: 0) {
                        Rectangle().fill(Palette.hairline).frame(height: 0.5)
                        Spacer(minLength: 0)
                    }
                    .frame(height: zoom.pointsPerHour)
                }
            }
            ForEach(placed, id: \.event.objectID) { item in
                block(item, day: day, columnWidth: width)
            }
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private func block(_ item: Placed, day: Date, columnWidth: CGFloat) -> some View {
        let event = item.event
        let top = yOffset(for: max(event.startAt ?? day, dayStart(day)), day: day)
        let bottom = yOffset(for: min(event.endAt ?? day, dayEnd(day)), day: day)
        let slotWidth = (columnWidth - 2) / CGFloat(item.lanes)
        let busy = EventPresentation.isBusyOnly(event, for: viewer, in: household)
        let token = EventService.subjects(of: event).first?.colorToken ?? "person1"
        let tint = busy ? Palette.busy : Palette.color(token)

        let isDragging = draggingID == event.objectID
        let hasOpen = !RequiredRoles.decode(event.requiredRolesRaw)
            .filter { !EventService.coveredRoles(of: event).contains($0) }.isEmpty

        return VStack(alignment: .leading, spacing: 1) {
            if isDragging {
                Text(movedLabel(event, columnWidth: columnWidth))
                    .font(.system(size: 9, weight: .bold))
            }
            Text(EventPresentation.title(of: event, for: viewer, in: household))
                .font(.system(size: 9, weight: .medium))
                .lineLimit(3)
        }
            .padding(2)
            .frame(width: max(slotWidth - 1, 4), height: max(bottom - top, 10), alignment: .topLeading)
            .background(tint.opacity(isDragging ? 0.45 : 0.22), in: RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .leading) {
                Rectangle().fill(tint).frame(width: 2)
            }
            .overlay(alignment: .topTrailing) {
                if hasOpen {
                    Circle().fill(Palette.color("person5")).frame(width: 7, height: 7).padding(2)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { onSelect(event) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("week.event.\(EventPresentation.title(of: event, for: viewer, in: household))")
            .gesture(moveGesture(for: event, columnWidth: columnWidth),
                     including: canMove(event) ? .all : .subviews)
            .gesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in onShowDetails(event) },
                     including: canMove(event) ? .subviews : .all)
            .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: 4, y: 2)
            .zIndex(isDragging ? 10 : 0)
            .offset(x: 1 + slotWidth * CGFloat(item.lane) + (isDragging ? dragOffset.width : 0),
                    y: max(top, 0) + (isDragging ? dragOffset.height : 0))
    }

    // MARK: - Verschieben über Tage

    private func moveGesture(for event: CDEvent, columnWidth: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag) = value {
                    draggingID = event.objectID
                    dragOffset = drag?.translation ?? .zero
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    let (days, minutes) = snapped(drag.translation, columnWidth: columnWidth)
                    if days != 0 || minutes != 0 { onMove(event, days, minutes) }
                }
                draggingID = nil
                dragOffset = .zero
                lastDragEnd = Date()
            }
    }

    private func snapped(_ translation: CGSize, columnWidth: CGFloat) -> (Int, Int) {
        let days = Int((translation.width / max(columnWidth, 1)).rounded())
        let minutes = Double(translation.height / zoom.pointsPerHour * 60)
        return (days, Int((minutes / Double(snapMinutes)).rounded()) * snapMinutes)
    }

    private func movedLabel(_ event: CDEvent, columnWidth: CGFloat) -> String {
        let (days, minutes) = snapped(dragOffset, columnWidth: columnWidth)
        let start = event.startAt ?? Date()
        let shifted = (Calendar.current.date(byAdding: .day, value: days, to: start) ?? start)
            .addingTimeInterval(TimeInterval(minutes * 60))
        return shifted.formatted(.dateTime.weekday(.abbreviated).hour().minute()
                                   .locale(Locale(identifier: "de_DE")))
    }

    // MARK: - Überschneidungen

    struct Placed {
        let event: CDEvent
        var lane: Int
        var lanes: Int
    }

    /// Überlappende Termine nebeneinander: einfache Spurvergabe je Gruppe.
    private func layout(_ items: [CDEvent], day: Date) -> [Placed] {
        let sorted = items.sorted { ($0.startAt ?? day) < ($1.startAt ?? day) }
        var result: [Placed] = []
        var group: [Int] = []          // Indizes in result der aktuellen Gruppe
        var laneEnds: [Date] = []
        var groupEnd = Date.distantPast

        func closeGroup() {
            let count = max(laneEnds.count, 1)
            for index in group { result[index].lanes = count }
            group.removeAll()
            laneEnds.removeAll()
        }

        for event in sorted {
            let start = event.startAt ?? day
            let end = event.endAt ?? start
            if start >= groupEnd { closeGroup() }
            let lane = laneEnds.firstIndex { $0 <= start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(end) } else { laneEnds[lane] = end }
            result.append(Placed(event: event, lane: lane, lanes: 1))
            group.append(result.count - 1)
            groupEnd = max(groupEnd, end)
        }
        closeGroup()
        return result
    }

    // MARK: - Hilfen

    private func eventsOn(_ day: Date) -> [CDEvent] {
        let start = dayStart(day), end = dayEnd(day)
        return events.filter { ($0.startAt ?? .distantFuture) < end && ($0.endAt ?? .distantPast) > start }
    }

    private func dayStart(_ day: Date) -> Date { Calendar.current.startOfDay(for: day) }

    private func dayEnd(_ day: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart(day)) ?? day
    }

    private func yOffset(for date: Date, day: Date) -> CGFloat {
        let origin = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: day) ?? day
        return CGFloat(date.timeIntervalSince(origin) / 3600) * zoom.pointsPerHour
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40).onEnded { value in
            // Nach einem Verschieben über Tage darf die Woche nicht zusätzlich umblättern.
            guard draggingID == nil, Date().timeIntervalSince(lastDragEnd) > 0.6 else { return }
            let dx = value.translation.width, dy = value.translation.height
            guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
            onSwipeWeek(dx < 0 ? 1 : -1)
        }
    }
}
