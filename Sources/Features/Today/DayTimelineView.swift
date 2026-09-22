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

    private let laneMinWidth: CGFloat = 96
    private let gutterWidth: CGFloat = 44
    private let startHour = 6
    private let endHour = 23

    public init(day: Date, members: [CDMember], events: [CDEvent], zoom: Binding<DayZoom>) {
        self.day = day
        self.members = members
        self.events = events
        self._zoom = zoom
    }

    public var body: some View {
        GeometryReader { geometry in
            let laneWidth = max(laneMinWidth,
                                (geometry.size.width - gutterWidth) / CGFloat(max(members.count, 1)))
            VStack(spacing: 0) {
                laneHeaders(laneWidth: laneWidth)
                Divider().overlay(Palette.hairline)
                ScrollView(.vertical, showsIndicators: false) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        timelineBody(laneWidth: laneWidth)
                    }
                }
            }
        }
        .background(Palette.surfaceSunken)
        .gesture(magnification)
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
                .frame(width: laneWidth)
                .padding(.vertical, Spacing.s)
            }
        }
        .background(Palette.surface)
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
        .padding(.bottom, Spacing.xxl)
    }

    private func hourGutter(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(TypeScale.hourLabel)
                    .foregroundStyle(.tertiary)
                    .frame(height: zoom.pointsPerHour, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, Spacing.s)
            }
        }
        .frame(width: gutterWidth, height: height, alignment: .top)
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
    }

    private func eventBlock(_ event: CDEvent, member: CDMember, width: CGFloat) -> some View {
        let top = yOffset(for: event.startAt ?? day)
        let bottom = yOffset(for: event.endAt ?? day)
        let duration = (event.endAt ?? day).timeIntervalSince(event.startAt ?? day)
        let isBusyOnly = EventVisibility(rawValue: event.visibilityRaw ?? "") == .busyOnly
        let tint = isBusyOnly ? Palette.busy : Palette.color(member.colorToken ?? "person1")

        return VStack(alignment: .leading, spacing: Spacing.hair) {
            if duration >= zoom.minimumLabelDuration {
                Text(event.title ?? "Ohne Titel")
                    .font(TypeScale.eventTitle)
                    .lineLimit(2)
                if duration >= zoom.minimumLabelDuration * 2, let location = event.locationName, !location.isEmpty {
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
               height: max(bottom - top, 12),
               alignment: .topLeading)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .offset(x: Spacing.xs, y: max(top, 0))
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
