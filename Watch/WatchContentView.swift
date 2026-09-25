import SwiftUI

struct WatchContentView: View {

    @EnvironmentObject private var store: WatchStore
    private let de = Locale(identifier: "de_DE")

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = store.snapshot {
                    list(snapshot)
                } else {
                    ContentUnavailableView("Noch keine Daten",
                                           systemImage: "iphone",
                                           description: Text("Family Planner einmal auf dem iPhone öffnen."))
                }
            }
            .navigationTitle("Familie")
        }
    }

    private func list(_ snapshot: WatchSnapshot) -> some View {
        List {
            if let status = store.status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }

            if snapshot.canClaim && !snapshot.open.isEmpty {
                Section("Noch offen") {
                    ForEach(snapshot.open) { open in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(open.roleLabel): \(open.title)").font(.headline)
                            Text(open.start.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(de)))
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Übernehme ich") { store.claim(open) }
                                .tint(.orange)
                        }
                    }
                }
            }

            ForEach(days(snapshot), id: \.0) { day, items in
                Section(dayTitle(day)) {
                    ForEach(items) { item in row(item) }
                }
            }

            Text("Stand: \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func row(_ item: WatchSnapshot.Item) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(rgb: item.rgb))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(2)
                Text(timeText(item) + (item.people.isEmpty ? "" : " · \(item.people)"))
                    .font(.footnote).foregroundStyle(.secondary)
                if let location = item.location, !location.isEmpty {
                    Text(location).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                if !item.openRoles.isEmpty {
                    Text(item.openRoles.map { "\($0) ?" }.joined(separator: " · "))
                        .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                }
            }
        }
    }

    private func timeText(_ item: WatchSnapshot.Item) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute().locale(de)
        return "\(item.start.formatted(style))–\(item.end.formatted(style))"
    }

    private func days(_ snapshot: WatchSnapshot) -> [(Date, [WatchSnapshot.Item])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: snapshot.events) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.start < $1.start }) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Heute" }
        if calendar.isDateInTomorrow(day) { return "Morgen" }
        return day.formatted(.dateTime.weekday(.wide).day().month().locale(de))
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
