import SwiftUI
import CoreData

/// Suche über alle Termine: Titel, Ort und Notizen. Treffer öffnen den passenden Tag.
struct SearchScreen: View {

    let viewer: CDMember?
    let household: CDHousehold?
    let onOpenDay: (Date) -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [CDEvent] = []

    var body: some View {
        NavigationStack {
            List {
                if !upcoming.isEmpty {
                    Section("Kommend") {
                        ForEach(upcoming, id: \.objectID, content: row)
                    }
                }
                if !past.isEmpty {
                    Section("Vergangen") {
                        ForEach(past.reversed(), id: \.objectID, content: row)
                    }
                }
            }
            .overlay {
                if query.trimmed.count >= 2 && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if query.trimmed.count < 2 {
                    ContentUnavailableView("Termine suchen",
                                           systemImage: "magnifyingglass",
                                           description: Text("Titel, Ort oder Notiz eingeben, z. B. „Schwimmen“ oder „Hasenweg“."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Titel, Ort, Notiz")
            .onChange(of: query) { _, _ in search() }
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("search.done")
                }
            }
        }
    }

    private var upcoming: [CDEvent] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return results.filter { ($0.endAt ?? .distantPast) >= startOfToday }
    }

    private var past: [CDEvent] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return results.filter { ($0.endAt ?? .distantPast) < startOfToday }
    }

    private func row(_ event: CDEvent) -> some View {
        Button {
            if let start = event.startAt { onOpenDay(start) }
            dismiss()
        } label: {
            HStack(spacing: Spacing.m) {
                let tint = Palette.color(EventService.subjects(of: event).first?.colorToken ?? "person1")
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(EventPresentation.title(of: event, for: viewer, in: household))
                    Text(subtitle(for: event))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search.result.\(EventPresentation.title(of: event, for: viewer, in: household))")
    }

    private func subtitle(for event: CDEvent) -> String {
        var parts: [String] = []
        if let start = event.startAt {
            let format: Date.FormatStyle = event.isAllDay
                ? .dateTime.weekday(.abbreviated).day().month()
                : .dateTime.weekday(.abbreviated).day().month().hour().minute()
            parts.append(start.formatted(format.locale(Locale(identifier: "de_DE"))) + (event.isAllDay ? " · ganztägig" : ""))
        }
        let names = EventService.subjects(of: event).compactMap(\.shortName)
        if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        if let location = EventPresentation.location(of: event, for: viewer, in: household), !location.isEmpty {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }

    private func search() {
        let text = query.trimmed
        guard text.count >= 2 else { results = []; return }
        let found = (try? context.fetch(EventService.searchRequest(text))) ?? []
        // Was die Kinderansicht ausblendet, darf die Suche nicht über den Titel finden.
        results = found.filter {
            EventPresentation.title(of: $0, for: viewer, in: household) == ($0.title ?? "")
                || EventPresentation.title(of: $0, for: viewer, in: household)
                    .localizedCaseInsensitiveContains(text)
        }
    }
}
