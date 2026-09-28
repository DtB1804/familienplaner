import SwiftUI
import CoreData

/// Die Kernansicht: ein vertikaler Zeitstrahl, eine Spalte pro Person.
///
/// Bewusst kein klassisches Wochenraster. Die Frage im Familienalltag lautet
/// "wer ist wann gebunden und wo überlappt es", und die beantwortet ein
/// Nebeneinander von Personen deutlich schneller als ein Nebeneinander von Tagen.
public struct DayTimelineView: View {

    let day: Date
    let members: [CDMember]
    let events: [CDEvent]
    @Binding var zoom: DayZoom
    var viewer: CDMember? = nil
    var household: CDHousehold? = nil
    var onSelect: ((CDEvent) -> Void)? = nil
    /// Gedrückthalten auf einem Termin, der nicht verschoben werden kann: Details zeigen.
    var onShowDetails: ((CDEvent) -> Void)? = nil
    /// Zeitpunkt des letzten Ziehens; kurz danach wird kein Tageswechsel per Wischen ausgelöst.
    @State private var lastDragEnd = Date.distantPast
    /// Verschieben per Gedrückthalten und Ziehen. Liefert die Verschiebung in Sekunden.
    var onMove: ((CDEvent, TimeInterval) -> Void)? = nil
    var canMove: (CDEvent) -> Bool = { _ in false }
    /// Wischen nach links (+1) oder rechts (−1) blättert den Tag.
    var onSwipeDay: ((Int) -> Void)? = nil
    /// Seitlich in die Spalte einer anderen Person gezogen: Termin betrifft jetzt diese Person.
    var onReassign: ((CDEvent, CDMember, CDMember) -> Void)? = nil

    @State private var draggingID: NSManagedObjectID?
    @State private var draggingMemberID: NSManagedObjectID?
    @State private var dragDY: CGFloat = 0
    @State private var dragDX: CGFloat = 0
    /// Richtung eines Ziehvorgangs, festgelegt nach den ersten Punkten: entweder Uhrzeit
    /// (senkrecht) oder Person (seitlich), nie beides zugleich.
    @State private var dragAxis: Axis?

    /// Raster beim Verschieben.
    private let snapMinutes = 15
    private let laneMinWidth: CGFloat = 64
    private let gutterWidth: CGFloat = 44
    /// Normal 6–23 Uhr; frühere oder spätere Termine erweitern den Bereich (UX-Prüfung B8).
    private var startHour: Int { TimelineHours.range(for: events).lowerBound }
    private var endHour: Int { TimelineHours.range(for: events).upperBound }

    public init(day: Date, members: [CDMember], events: [CDEvent], zoom: Binding<DayZoom>,
                viewer: CDMember? = nil, household: CDHousehold? = nil,
                onSelect: ((CDEvent) -> Void)? = nil,
                onShowDetails: ((CDEvent) -> Void)? = nil,
                onMove: ((CDEvent, TimeInterval) -> Void)? = nil,
                canMove: @escaping (CDEvent) -> Bool = { _ in false },
                onSwipeDay: ((Int) -> Void)? = nil,
                onReassign: ((CDEvent, CDMember, CDMember) -> Void)? = nil) {
        self.day = day
        self.members = members
        self.events = events
        self._zoom = zoom
        self.viewer = viewer
        self.household = household
        self.onSelect = onSelect
        self.onShowDetails = onShowDetails
        self.onMove = onMove
        self.canMove = canMove
        self.onSwipeDay = onSwipeDay
        self.onReassign = onReassign
    }

    public var body: some View {
        GeometryReader { geometry in
            let laneWidth = max(laneMinWidth,
                                (geometry.size.width - gutterWidth) / CGFloat(max(members.count, 1)))
            // Bis etwa fünf Personen passt alles in die Breite; dann nur vertikal
            // scrollen, damit Wischen nach links/rechts den Tag wechseln kann.
            let needsHorizontal = gutterWidth + laneWidth * CGFloat(members.count) > geometry.size.width + 1
            // Kopfzeile fest oben, darunter genau ein Scrollbereich für beide Achsen.
            // Vorher: verschachtelte ScrollViews. Auf iOS 26 hat das die Kopfzeile
            // aufgebläht und den Zeitstrahl ans Ende gescrollt (Screenshot 23.09.2026).
            ScrollViewReader { proxy in
                ScrollView(needsHorizontal ? [.vertical, .horizontal] : .vertical, showsIndicators: false) {
                    timelineBody(laneWidth: laneWidth)
                }
                .simultaneousGesture(daySwipe)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        laneHeaders(laneWidth: laneWidth)
                        Rectangle().fill(Palette.hairline).frame(height: 0.5)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .onAppear { scrollToStart(proxy) }
                .onChange(of: day) { _, _ in scrollToStart(proxy) }
            }
        }
        .background(Palette.surfaceSunken)
        .gesture(magnification)
        .sensoryFeedback(.selection, trigger: draggingID)
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard draggingID == nil, Date().timeIntervalSince(lastDragEnd) > 0.6 else { return }
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                onSwipeDay?(dx < 0 ? 1 : -1)
            }
    }

    // MARK: - Kopfzeile

    private func laneHeaders(laneWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth)
            ForEach(members, id: \.objectID) { member in
                VStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(Palette.color(member.colorToken ?? "person1"))
                        .frame(width: 8, height: 8)
                    Text(member.shortName ?? "?")
                        .font(TypeScale.laneHeader)
                        .foregroundStyle(.primary)
                }
                .frame(width: laneWidth, height: 40)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
    }

    /// Heute: eine Stunde vor jetzt. Andere Tage: 7 Uhr.
    private func scrollToStart(_ proxy: ScrollViewProxy) {
        var hour = 7
        if Calendar.current.isDateInToday(day), !TestMode.isActive {
            hour = Calendar.current.component(.hour, from: Date()) - 1
        }
        hour = min(max(hour, startHour), endHour - 1)
        proxy.scrollTo(hour, anchor: .top)
    }

    // MARK: - Zeitstrahl

    private func timelineBody(laneWidth: CGFloat) -> some View {
        let hours = endHour - startHour
        let height = CGFloat(hours) * zoom.pointsPerHour

        return HStack(alignment: .top, spacing: 0) {
            hourGutter(height: height)
            ZStack(alignment: .topLeading) {
                hourLines(height: height, width: laneWidth * CGFloat(max(members.count, 1)))
                nowIndicator(width: laneWidth * CGFloat(max(members.count, 1)))
                HStack(spacing: 0) {
                    ForEach(members, id: \.objectID) { member in
                        lane(for: member, width: laneWidth, height: height)
                    }
                }
            }
            .frame(height: height, alignment: .top)
        }
        .padding(.bottom, 110)   // Platz unter der schwebenden Werkzeugleiste
    }

    private func hourGutter(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .id(hour)
                    .font(TypeScale.hourLabel)
                    .foregroundStyle(.tertiary)
                    .frame(height: zoom.pointsPerHour, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, Spacing.s)
            }
        }
        .frame(width: gutterWidth, height: height, alignment: .top)
        .accessibilityHidden(true)   // Uhrzeiten stehen im Vorlesetext jedes Termins
    }

    private func hourLines(height: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle().fill(Palette.hairline).frame(height: 0.5)
                    Spacer(minLength: 0)
                }
                .frame(height: zoom.pointsPerHour)
            }
        }
        .frame(width: width, height: height, alignment: .top)
    }

    @ViewBuilder
    private func nowIndicator(width: CGFloat) -> some View {
        if Calendar.current.isDateInToday(day) {
            let offset = yOffset(for: Date())
            if offset >= 0 {
                Rectangle()
                    .fill(Color.red.opacity(0.8))
                    .frame(width: width, height: 1)
                    .offset(y: offset)
            }
        }
    }

    // MARK: - Eine Spur

    private func lane(for member: CDMember, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Palette.surface.opacity(0.55))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Palette.hairline).frame(width: 0.5)
                }
            ForEach(events(for: member), id: \.objectID) { event in
                eventBlock(event, member: member, width: width)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        // Die gezogene Spalte liegt oben, sonst verschwindet der Termin hinter der Nachbarspalte.
        .zIndex(draggingMemberID == member.objectID ? 1 : 0)
    }

    private func eventBlock(_ event: CDEvent, member: CDMember, width: CGFloat) -> some View {
        let top = yOffset(for: event.startAt ?? day)
        let bottom = yOffset(for: event.endAt ?? day)
        let duration = (event.endAt ?? day).timeIntervalSince(event.startAt ?? day)
        let isBusyOnly = EventPresentation.isBusyOnly(event, for: viewer, in: household)
        let tint = isBusyOnly ? Palette.busy : Palette.color(member.colorToken ?? "person1")
        let baseTitle = EventPresentation.title(of: event, for: viewer, in: household)
        let location = EventPresentation.location(of: event, for: viewer, in: household)
        // In der Spalte des Fahrers steht die Aufgabe vor dem Titel, z. B. "Holt · Schwimmen".
        let ownRoles = roles(of: member, in: event)
        let title = ownRoles.contains(.subject) || ownRoles.isEmpty
            ? baseTitle
            : ownRoles.map(\.label).joined(separator: ", ") + " · " + baseTitle
        let assignments = ownRoles.contains(.subject) ? assignmentLine(for: event) : nil
        let openCount = ownRoles.contains(.subject) ? openRoleCount(for: event) : 0
        let isDragging = draggingID == event.objectID
        let movable = canMove(event)

        return VStack(alignment: .leading, spacing: Spacing.hair) {
            if isDragging {
                HStack(spacing: 4) {
                    Text(movedStart(event).formatted(date: .omitted, time: .shortened))
                    if let target = reassignTarget(from: member, laneWidth: width) {
                        Text("→ \(target.shortName ?? "")")
                    }
                }
                .font(TypeScale.eventMeta.weight(.semibold))
            }
            if duration >= zoom.minimumLabelDuration {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if SeriesService.isSeries(event) {
                        Image(systemName: "repeat")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(TypeScale.eventTitle)
                        .lineLimit(2)
                }
                if duration >= zoom.minimumLabelDuration * 2, let assignments {
                    Text(assignments)
                        .font(TypeScale.eventMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if duration >= zoom.minimumLabelDuration * 2, let location, !location.isEmpty {
                    Text(location)
                        .font(TypeScale.eventMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.hair)
        .frame(width: width - Spacing.xs * 2,
               height: max(bottom - top, 22),
               alignment: .topLeading)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .overlay(alignment: .bottomTrailing) {
            // Offene Zuständigkeit auch bei kurzen Terminen sichtbar, z. B. "Holt ?".
            // Unten rechts und in schmalen Spalten kurz ("2 ?"), damit der Titel lesbar bleibt.
            if openCount > 0 {
                Text(width < 140 ? "\(openCount) ?" : openLabel(for: event))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Palette.color("person5"), in: Capsule())
                    .foregroundStyle(.black)
                    .padding(3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onSelect?(event) }
        .gesture(moveGesture(for: event, member: member, laneWidth: width), including: movable ? .all : .subviews)
        // Halten bedeutet immer Ziehen; Details gibt es per Tippen (UX-Prüfung B9).
        .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 6, y: 2)
        .scaleEffect(isDragging ? 1.03 : 1)
        .zIndex(isDragging ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(event, title: title))
        .accessibilityHint(movable ? "Doppeltippen für Details. Weitere Aktionen zum Verschieben." : "Doppeltippen für Details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect?(event) }
        .accessibilityActions {
            if movable {
                Button("15 Minuten später") { onMove?(event, 15 * 60) }
                Button("15 Minuten früher") { onMove?(event, -15 * 60) }
                Button("1 Stunde später") { onMove?(event, 3600) }
                Button("1 Stunde früher") { onMove?(event, -3600) }
            }
        }
        .accessibilityIdentifier("event.\(baseTitle)")
        .accessibilityValue((event.startAt ?? day).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
        .offset(x: Spacing.xs + (isDragging && canReassign(event, from: member) ? dragDX : 0),
                y: max(top, 0) + (isDragging ? dragDY : 0))
    }

    /// Vorlesetext für VoiceOver, z. B. "Holt · Schwimmen, 17:00 bis 18:00, Mia, Bringt offen".
    private func spokenLabel(_ event: CDEvent, title: String) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))
        var parts = [title]
        if let start = event.startAt, let end = event.endAt {
            parts.append("\(start.formatted(style)) bis \(end.formatted(style))")
        }
        let names = EventService.subjects(of: event).compactMap(\.displayName)
        if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        let open = openRoles(for: event)
        if !open.isEmpty { parts.append(open.map { "\($0.label) offen" }.joined(separator: ", ")) }
        if SeriesService.isSeries(event) { parts.append("wiederholt sich") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Verschieben

    private func moveGesture(for event: CDEvent, member: CDMember, laneWidth: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag) = value {
                    draggingID = event.objectID
                    draggingMemberID = member.objectID
                    let translation = drag?.translation ?? .zero
                    if dragAxis == nil, translation.width * translation.width + translation.height * translation.height > 144 {
                        dragAxis = abs(translation.width) > abs(translation.height) && canReassign(event, from: member)
                            ? .horizontal : .vertical
                    }
                    dragDY = dragAxis == .vertical ? translation.height : 0
                    dragDX = dragAxis == .horizontal ? translation.width : 0
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    switch dragAxis {
                    case .vertical:
                        let minutes = snappedMinutes(for: drag.translation.height)
                        if minutes != 0 { onMove?(event, TimeInterval(minutes * 60)) }
                    case .horizontal:
                        if let target = reassignTarget(from: member, laneWidth: laneWidth, dx: drag.translation.width),
                           canReassign(event, from: member) {
                            onReassign?(event, member, target)
                        }
                    case nil:
                        break
                    }
                }
                draggingID = nil
                draggingMemberID = nil
                dragAxis = nil
                dragDY = 0
                dragDX = 0
                lastDragEnd = Date()
            }
    }

    /// Seitlich ziehen geht nur aus der Spalte einer betroffenen Person
    /// (nicht aus der Spalte dessen, der bringt oder holt).
    private func canReassign(_ event: CDEvent, from member: CDMember) -> Bool {
        onReassign != nil && roles(of: member, in: event).contains(.subject)
    }

    /// Zielperson nach seitlichem Ziehen um mindestens eine halbe Spaltenbreite.
    private func reassignTarget(from member: CDMember, laneWidth: CGFloat, dx: CGFloat? = nil) -> CDMember? {
        let shift = Int(((dx ?? dragDX) / max(laneWidth, 1)).rounded())
        guard shift != 0, let index = members.firstIndex(where: { $0.objectID == member.objectID }) else { return nil }
        let target = index + shift
        guard members.indices.contains(target) else { return nil }
        return members[target]
    }

    private func snappedMinutes(for dy: CGFloat) -> Int {
        let minutes = Double(dy / zoom.pointsPerHour * 60)
        return Int((minutes / Double(snapMinutes)).rounded()) * snapMinutes
    }

    private func movedStart(_ event: CDEvent) -> Date {
        (event.startAt ?? day).addingTimeInterval(TimeInterval(snappedMinutes(for: dragDY) * 60))
    }

    // MARK: - Zuständigkeiten

    private func roles(of member: CDMember, in event: CDEvent) -> [ParticipationRole] {
        ((event.participations as? Set<CDEventParticipation>) ?? [])
            .filter { $0.member?.objectID == member.objectID
                      && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined }
            .compactMap { ParticipationRole(rawValue: $0.roleRaw ?? "") }
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func openRoles(for event: CDEvent) -> [ParticipationRole] {
        let required = RequiredRoles.decode(event.requiredRolesRaw)
        let covered = EventService.coveredRoles(of: event)
        return required.filter { !covered.contains($0) }
    }

    private func openRoleCount(for event: CDEvent) -> Int { openRoles(for: event).count }

    private func openLabel(for event: CDEvent) -> String {
        openRoles(for: event).map { "\($0.label) ?" }.joined(separator: " · ")
    }

    /// z. B. "Bringt DB · Holt ?" – wer welche Zuständigkeit übernommen hat.
    private func assignmentLine(for event: CDEvent) -> String? {
        let required = RequiredRoles.decode(event.requiredRolesRaw)
        guard !required.isEmpty else { return nil }
        let participations = (event.participations as? Set<CDEventParticipation>) ?? []
        return required.map { role in
            let candidates = participations.filter {
                $0.roleRaw == role.rawValue && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined
            }
            let who = EventService.earliest(of: candidates)?.member?.shortName ?? "?"
            return "\(role.label) \(who)"
        }.joined(separator: " · ")
    }

    // MARK: - Hilfsrechnungen

    private func events(for member: CDMember) -> [CDEvent] {
        events.filter { event in
            guard let participations = event.participations as? Set<CDEventParticipation> else { return false }
            return participations.contains { $0.member?.objectID == member.objectID }
        }
    }

    private func yOffset(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        let dayStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day) ?? day
        let minutes = date.timeIntervalSince(dayStart) / 60
        return CGFloat(minutes) / 60 * zoom.pointsPerHour
    }

    // MARK: - Zoom

    private var magnification: some Gesture {
        MagnifyGesture()
            .onEnded { value in
                withAnimation(.snappy(duration: 0.22)) {
                    zoom = value.magnification > 1 ? zoom.zoomedIn() : zoom.zoomedOut()
                }
            }
    }
}

/// Sichtbarer Stundenbereich des Zeitstrahls: mindestens 6–23 Uhr, erweitert um Termine
/// davor oder danach. Termine über Mitternacht reichen bis 24 Uhr.
enum TimelineHours {
    static let defaultStart = 6
    static let defaultEnd = 23

    static func range(for events: [CDEvent]) -> ClosedRange<Int> {
        let calendar = Calendar.current
        var start = defaultStart
        var end = defaultEnd
        for event in events where !event.isAllDay {
            guard let begin = event.startAt, let finish = event.endAt else { continue }
            start = min(start, calendar.component(.hour, from: begin))
            if !calendar.isDate(finish, inSameDayAs: begin) {
                end = 24
            } else {
                let hour = calendar.component(.hour, from: finish)
                let minute = calendar.component(.minute, from: finish)
                end = max(end, hour + (minute > 0 ? 1 : 0))
            }
        }
        return max(0, start)...min(24, max(end, start + 1))
    }
}
