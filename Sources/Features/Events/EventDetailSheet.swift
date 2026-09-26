import SwiftUI
import CoreData

/// Nur-Lese-Ansicht eines Termins: genaue Zeiten, Personen, Zuständigkeiten, Herkunft.
/// Für übernommene Kalendertermine (bearbeitet wird in der Kalender-App) und für alle,
/// die nicht bearbeiten dürfen (Kinder, Vorschau).
struct EventDetailSheet: View {

    @ObservedObject var event: CDEvent
    let viewer: CDMember?
    let household: CDHousehold?

    @Environment(\.dismiss) private var dismiss

    private let de = Locale(identifier: "de_DE")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(EventPresentation.title(of: event, for: viewer, in: household))
                        .font(.title3.weight(.semibold))
                    LabeledContent("Datum", value: dateText)
                    LabeledContent("Zeit", value: timeText)
                    LabeledContent("Dauer", value: durationText)
                    if let rule = SeriesService.rule(of: event) {
                        LabeledContent("Wiederholung", value: RepeatChoice(rule).label
                            + (rule.until.map { " bis " + $0.formatted(.dateTime.day().month().year().locale(de)) } ?? ""))
                    }
                    if let location = EventPresentation.location(of: event, for: viewer, in: household),
                       !location.isEmpty {
                        LabeledContent("Ort", value: location)
                    }
                }

                Section("Für wen") {
                    let names = EventService.subjects(of: event).compactMap(\.displayName)
                    Text(names.isEmpty ? "–" : names.joined(separator: ", "))
                }

                if !assignments.isEmpty {
                    Section("Zuständigkeiten") {
                        ForEach(assignments, id: \.self) { Text($0) }
                    }
                }

                if !hidesDetails, let notes = event.notes, !notes.isEmpty {
                    Section("Notizen") { Text(notes) }
                }

                if isImported {
                    Section {
                        Label(sourceText, systemImage: "calendar.badge.checkmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isImported ? "Aus Kalender" : "Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Texte

    private var isImported: Bool { EventOrigin(rawValue: event.originRaw ?? "") == .imported }

    private var hidesDetails: Bool {
        EventPresentation.isBusyOnly(event, for: viewer, in: household)
    }

    private var dateText: String {
        guard let start = event.startAt else { return "–" }
        let startDay = start.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(de))
        if let end = event.endAt, !Calendar.current.isDate(start, inSameDayAs: end.addingTimeInterval(-1)) {
            return "\(startDay) bis \(end.formatted(.dateTime.weekday(.abbreviated).day().month().locale(de)))"
        }
        return startDay
    }

    private var timeText: String {
        guard let start = event.startAt, let end = event.endAt else { return "–" }
        let time = Date.FormatStyle.dateTime.hour().minute().locale(de)
        return "\(start.formatted(time)) – \(end.formatted(time)) Uhr"
    }

    private var durationText: String {
        guard let start = event.startAt, let end = event.endAt else { return "–" }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) Min."
        case (_, 0): return "\(hours) Std."
        default: return "\(hours) Std. \(rest) Min."
        }
    }

    private var assignments: [String] {
        let required = RequiredRoles.decode(event.requiredRolesRaw)
        guard !required.isEmpty else { return [] }
        let participations = (event.participations as? Set<CDEventParticipation>) ?? []
        return required.map { role in
            let candidates = participations.filter {
                $0.roleRaw == role.rawValue && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined
            }
            let who = EventService.earliest(of: candidates)?.member?.displayName ?? "noch offen"
            return "\(role.label): \(who)"
        }
    }

    private var sourceText: String {
        let importer = ((household?.members as? Set<CDMember>) ?? [])
            .first { $0.id == event.createdByMemberID }?.displayName
        let who = importer.map { "von \($0) " } ?? ""
        return "Aus dem iPhone-Kalender \(who)übernommen. Geändert wird er dort; die Änderung kommt automatisch hierher."
    }
}
