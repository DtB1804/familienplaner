import SwiftUI
import CoreData

/// Ganztägige Termine (Urlaub, Ferien, Geburtstage) als Leiste über dem Zeitstrahl.
/// In der Woche mit Zeitraum, am Tag nur mit Titel und Personen.
struct AllDayStrip: View {

    let events: [CDEvent]
    let showsDates: Bool
    let viewer: CDMember?
    let household: CDHousehold?
    let onSelect: (CDEvent) -> Void

    private let de = Locale(identifier: "de_DE")

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(events, id: \.objectID) { event in
                    chip(event)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.xs)
        }
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
        .accessibilityIdentifier("allday.strip")
    }

    private func chip(_ event: CDEvent) -> some View {
        let subjects = EventService.subjects(of: event)
        let busy = EventPresentation.isBusyOnly(event, for: viewer, in: household)
        let tint = busy ? Palette.busy : Palette.color(subjects.first?.colorToken ?? "person1")
        let title = EventPresentation.title(of: event, for: viewer, in: household)
        let names = subjects.compactMap(\.shortName).joined(separator: ", ")
        return Button { onSelect(event) } label: {
            HStack(spacing: 4) {
                if SeriesService.isSeries(event) {
                    Image(systemName: "repeat").font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title).font(TypeScale.eventTitle).lineLimit(1)
                if showsDates, let range = rangeText(event) {
                    Text(range).font(TypeScale.eventMeta).foregroundStyle(.secondary)
                }
                if !names.isEmpty {
                    Text(names).font(TypeScale.eventMeta).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("allday.\(title)")
    }

    private func rangeText(_ event: CDEvent) -> String? {
        guard let start = event.startAt, let last = EventService.lastDay(of: event) else { return nil }
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().locale(de)
        return Calendar.current.isDate(start, inSameDayAs: last)
            ? start.formatted(style)
            : "\(start.formatted(style))–\(last.formatted(style))"
    }
}
