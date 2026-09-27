import SwiftUI
import WidgetKit

/// Zifferblatt-Elemente (Komplikationen) der Apple Watch.
///
/// Datenquelle ist der Ausschnitt, den die Watch-App vom iPhone bekommt und in die App Group
/// der Watch schreibt (`WidgetBridge`). Kein Core Data, kein CloudKit (Regel 15, 19).
@main
struct FamilienplanerWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextEventComplication()
        OpenComplication()
    }
}

// MARK: - Zeitleiste

struct WatchEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?

    var next: WatchSnapshot.Item? {
        (snapshot?.events ?? [])
            .filter { $0.end > date && $0.allDay != true }
            .min { $0.start < $1.start }
    }

    var open: [WatchSnapshot.Open] {
        guard snapshot?.canClaim == true else { return [] }
        return (snapshot?.open ?? []).filter { $0.start > date }.sorted { $0.start < $1.start }
    }
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: Date(), snapshot: .complicationSample) }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: Date(), snapshot: WidgetBridge.load() ?? (context.isPreview ? .complicationSample : nil)))
    }

    /// Ein Eintrag jetzt und nach jedem Terminende der nächsten 24 Stunden.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetBridge.load()
        let ends = Set((snapshot?.events ?? []).map(\.end).filter { $0 > now && $0 < now.addingTimeInterval(86_400) })
        let entries = [WatchEntry(date: now, snapshot: snapshot)]
            + ends.sorted().prefix(30).map { WatchEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Nächster Termin

struct NextEventComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchNextEvent", provider: WatchProvider()) { entry in
            NextEventView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Nächster Termin")
        .description("Der nächste Familientermin.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
    }
}

struct NextEventView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let next = entry.next {
                Text("\(ComplicationText.time(next.start)) \(next.title)")
            } else {
                Text("Keine Termine")
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                if let next = entry.next {
                    VStack(spacing: 0) {
                        Image(systemName: "calendar").font(.system(size: 11)).widgetAccentable()
                        Text(ComplicationText.time(next.start)).font(.system(size: 13, weight: .semibold))
                            .minimumScaleFactor(0.6)
                    }
                } else {
                    Image(systemName: "calendar")
                }
            }
        case .accessoryCorner:
            Image(systemName: "calendar")
                .widgetLabel {
                    Text(entry.next.map { "\(ComplicationText.time($0.start)) \($0.title)" } ?? "Frei")
                }
        default:
            if let next = entry.next {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(complicationRGB: next.rgb))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ComplicationText.dayAndTime(next.start, now: entry.date))
                            .font(.caption2).widgetAccentable()
                        Text(next.title).font(.headline).lineLimit(1)
                        if !next.openRoles.isEmpty {
                            Text(next.openRoles.joined(separator: ", ") + " ?").font(.caption2)
                        } else if !next.people.isEmpty {
                            Text(next.people).font(.caption2).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text(entry.snapshot == nil ? "iPhone-App öffnen" : "Keine Termine")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Offene Zuständigkeiten

struct OpenComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchOpen", provider: WatchProvider()) { entry in
            OpenComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Offen")
        .description("Offene Zuständigkeiten (Bringen, Holen, Begleiten).")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct OpenComplicationView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.open.isEmpty ? "Alles vergeben" : "\(entry.open.count) offen")
        case .accessoryCorner:
            Text("\(entry.open.count)")
                .font(.title3.weight(.bold))
                .widgetLabel { Text("offen") }
        case .accessoryRectangular:
            if let first = entry.open.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(entry.open.count) offen").font(.caption2).widgetAccentable()
                    Text("\(first.roleLabel): \(first.title)").font(.headline).lineLimit(1)
                    Text(ComplicationText.dayAndTime(first.start, now: entry.date)).font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Alles vergeben", systemImage: "checkmark.circle")
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.open.count)").font(.system(size: 20, weight: .bold)).widgetAccentable()
                    Text("offen").font(.system(size: 9))
                }
            }
        }
    }
}

// MARK: - Hilfen

enum ComplicationText {
    static let de = Locale(identifier: "de_DE")

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(de))
    }

    static func dayAndTime(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Heute"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "Morgen"
        } else {
            day = date.formatted(.dateTime.weekday(.abbreviated).locale(de))
        }
        return "\(day), \(time(date))"
    }
}

extension Color {
    /// Personenfarbe aus dem Ausschnitt (Dunkelmodus-Wert, die Watch ist dunkel).
    init(complicationRGB rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}

extension WatchSnapshot {
    static var complicationSample: WatchSnapshot {
        let now = Date()
        return WatchSnapshot(
            generatedAt: now, viewerName: "Ich", canClaim: true,
            events: [.init(id: "1", title: "Schwimmen", start: now.addingTimeInterval(3600),
                           end: now.addingTimeInterval(7200), location: nil, people: "MI",
                           rgb: 0x5BC0EB, openRoles: ["Holt"], busy: false)],
            open: [.init(eventID: "1", role: "driveFrom", roleLabel: "Holt", title: "Schwimmen",
                         start: now.addingTimeInterval(3600))])
    }
}
