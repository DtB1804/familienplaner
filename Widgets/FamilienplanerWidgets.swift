import SwiftUI
import WidgetKit

/// Widgets für Home- und Sperrbildschirm. Datenquelle ist ausschließlich der Ausschnitt,
/// den die App in die App Group schreibt (`WidgetBridge`). Titel sind darin bereits für
/// das Mitglied dieses Geräts reduziert ("Belegt", Kinderansicht).
@main
struct FamilienplanerWidgets: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
        OpenWidget()
    }
}

// MARK: - Zeitleiste

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?

    /// Termine, die zum Zeitpunkt dieses Eintrags noch nicht vorbei sind.
    var upcoming: [WatchSnapshot.Item] {
        // Nach Tag, ganztägige zuerst, dann nach Beginn.
        let calendar = Calendar.current
        func key(_ item: WatchSnapshot.Item) -> (Date, Int, Date) {
            (calendar.startOfDay(for: max(item.start, date)), item.allDay == true ? 0 : 1, item.start)
        }
        return (snapshot?.events ?? []).filter { $0.end > date }.sorted { key($0) < key($1) }
    }

    var open: [WatchSnapshot.Open] {
        guard snapshot?.canClaim == true else { return [] }
        return (snapshot?.open ?? []).filter { $0.start > date }.sorted { $0.start < $1.start }
    }
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetBridge.load() ?? (context.isPreview ? .sample : nil)))
    }

    /// Ein Eintrag jetzt und einer nach jedem Terminende der nächsten 24 Stunden, damit der
    /// nächste Termin nachrückt, ohne dass die App laufen muss. Neue Daten meldet die App.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetBridge.load()
        let horizon = now.addingTimeInterval(24 * 3600)
        var dates = Set((snapshot?.events ?? []).map(\.end).filter { $0 > now && $0 < horizon })
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
            dates.insert(midnight)
        }
        let entries = [SnapshotEntry(date: now, snapshot: snapshot)]
            + dates.sorted().prefix(40).map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget "Nächste Termine"

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingWidget", provider: SnapshotProvider()) { entry in
            UpcomingView(entry: entry)
        }
        .configurationDisplayName("Nächste Termine")
        .description("Die nächsten Termine der Familie, die dich betreffen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct UpcomingView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(WidgetBridge.dayURL(entry.upcoming.first.map { max($0.start, entry.date) } ?? entry.date))
            .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    @ViewBuilder private var content: some View {
        if entry.snapshot == nil {
            EmptyHint(text: "Family Planner einmal öffnen")
        } else {
            switch family {
            case .accessoryInline:
                if let next = entry.upcoming.first {
                    Text("\(WidgetText.time(next, now: entry.date)) \(next.title)")
                } else {
                    Text("Keine Termine")
                }
            case .accessoryRectangular:
                if let next = entry.upcoming.first {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WidgetText.dayAndTime(next, now: entry.date)).font(.caption2).widgetAccentable()
                        Text(next.title).font(.headline).lineLimit(1)
                        if !next.people.isEmpty { Text(next.people).font(.caption2).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Keine Termine").font(.caption)
                }
            default:
                list
            }
        }
    }

    private var limit: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 9
        }
    }

    private var list: some View {
        let items = Array(entry.upcoming.prefix(limit))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(WidgetText.heading(items.first, now: entry.date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !entry.open.isEmpty {
                    Label("\(entry.open.count)", systemImage: "questionmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.color("person5"))
                }
            }
            if items.isEmpty {
                Spacer()
                Text("Keine Termine in den nächsten Tagen").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0, WidgetText.dayChanged(items[index - 1], item, now: entry.date) {
                        Text(WidgetText.heading(item, now: entry.date))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    ItemRow(item: item, now: entry.date, compact: family == .systemSmall)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct ItemRow: View {
    let item: WatchSnapshot.Item
    let now: Date
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Palette.color(item.token ?? (item.busy ? "busy" : "person1")))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.caption.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(WidgetText.time(item, now: now))
                    if !compact, !item.people.isEmpty { Text(item.people) }
                    if !item.openRoles.isEmpty {
                        Text(item.openRoles.joined(separator: ", ") + " ?")
                            .fontWeight(.bold)
                            .foregroundStyle(Palette.color("person5"))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Widget "Offen"

struct OpenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenWidget", provider: SnapshotProvider()) { entry in
            OpenView(entry: entry)
        }
        .configurationDisplayName("Offene Zuständigkeiten")
        .description("Wer bringt, holt oder begleitet noch nicht feststeht.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct OpenView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(WidgetBridge.dayURL(entry.open.first?.start ?? entry.date))
            .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.open.count)").font(.title2.weight(.bold)).widgetAccentable()
                    Text("offen").font(.system(size: 9))
                }
            }
        case .accessoryRectangular:
            if let next = entry.open.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(entry.open.count) offen").font(.caption2).widgetAccentable()
                    Text("\(next.roleLabel): \(next.title)").font(.headline).lineLimit(1)
                    Text(WidgetText.dayAndTime(next.start, now: entry.date)).font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Alles vergeben", systemImage: "checkmark.circle")
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Offen").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if entry.snapshot == nil {
                    EmptyHint(text: "Family Planner einmal öffnen")
                } else if entry.open.isEmpty {
                    Spacer()
                    Label("Alles vergeben", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                } else {
                    Text("\(entry.open.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.color("person5"))
                    ForEach(entry.open.prefix(2)) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(item.roleLabel): \(item.title)").font(.caption.weight(.semibold)).lineLimit(1)
                            Text(WidgetText.dayAndTime(item.start, now: entry.date))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Hilfen

struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
}

enum WidgetText {
    static let de = Locale(identifier: "de_DE")

    static func time(_ item: WatchSnapshot.Item, now: Date) -> String {
        if item.allDay == true { return "ganztägig" }
        let style = Date.FormatStyle.dateTime.hour().minute().locale(de)
        return "\(item.start.formatted(style))–\(item.end.formatted(style))"
    }

    static func dayLabel(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Heute" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Morgen"
        }
        return date.formatted(.dateTime.weekday(.wide).locale(de))
    }

    static func heading(_ item: WatchSnapshot.Item?, now: Date) -> String {
        guard let item else { return "Heute" }
        return dayLabel(max(item.start, now), now: now)
    }

    static func dayChanged(_ a: WatchSnapshot.Item, _ b: WatchSnapshot.Item, now: Date) -> Bool {
        !Calendar.current.isDate(max(a.start, now), inSameDayAs: max(b.start, now))
    }

    static func dayAndTime(_ item: WatchSnapshot.Item, now: Date) -> String {
        item.allDay == true ? "\(dayLabel(max(item.start, now), now: now)), ganztägig" : dayAndTime(item.start, now: now)
    }

    static func dayAndTime(_ date: Date, now: Date) -> String {
        "\(dayLabel(date, now: now)), \(date.formatted(.dateTime.hour().minute().locale(de)))"
    }
}

extension WatchSnapshot {
    /// Beispiel für die Widget-Galerie.
    static var sample: WatchSnapshot {
        let now = Date()
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }
        return WatchSnapshot(
            generatedAt: now, viewerName: "Ich", canClaim: true,
            events: [
                .init(id: "1", title: "Schwimmen", start: at(1), end: at(2), location: nil, people: "MI",
                      rgb: 0, openRoles: ["Holt"], busy: false, token: "person2"),
                .init(id: "2", title: "Elternabend", start: at(4), end: at(5.5), location: nil, people: "ICH",
                      rgb: 0, openRoles: [], busy: false, token: "person1"),
                .init(id: "3", title: "Belegt", start: at(20), end: at(28), location: nil, people: "",
                      rgb: 0, openRoles: [], busy: true, token: "busy")
            ],
            open: [.init(eventID: "1", role: "driveFrom", roleLabel: "Holt", title: "Schwimmen", start: at(1))])
    }
}
