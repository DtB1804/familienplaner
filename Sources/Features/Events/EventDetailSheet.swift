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

    @State private var pendingClaimRole: ParticipationRole?
    @State private var claimMessage: String?

    private let de = Locale(identifier: "de_DE")

    /// Übernehmen dürfen Erwachsene; in der Kindervorschau ist `viewer` das Kind.
    private var canClaim: Bool { viewer?.role == .adult }

    private struct Assignment {
        let role: ParticipationRole
        let who: String?
    }

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
                        ForEach(assignments, id: \.role) { item in
                            HStack {
                                Text("\(item.role.label): \(item.who ?? "noch offen")")
                                Spacer()
                                if item.who == nil && canClaim {
                                    Button("Übernehme ich") {
                                        if SeriesService.isSeries(event) { pendingClaimRole = item.role }
                                        else { claim(item.role, scope: .single) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("detail.claim.\(item.role.rawValue)")
                                }
                            }
                        }
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
        .confirmationDialog(pendingClaimRole.map { "\($0.label) übernehmen" } ?? "",
                            isPresented: Binding(get: { pendingClaimRole != nil },
                                                 set: { if !$0 { pendingClaimRole = nil } }),
                            titleVisibility: .visible) {
            if let role = pendingClaimRole {
                Button("Für die ganze Serie") { claim(role, scope: .series) }
                Button("Nur diesen Termin") { claim(role, scope: .single) }
            }
        }
        .alert("Nicht übernommen",
               isPresented: Binding(get: { claimMessage != nil }, set: { if !$0 { claimMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(claimMessage ?? "")
        }
    }

    private func claim(_ role: ParticipationRole, scope: ClaimActions.Scope) {
        pendingClaimRole = nil
        guard let id = event.id else { return }
        switch ClaimActions.claim(eventID: id, role: role, scope: scope) {
        case .claimed: break
        case .alreadyTaken(let name): claimMessage = "\(role.label) übernimmt bereits \(name)."
        case .notPossible(let reason): claimMessage = reason
        }
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
            if event.isAllDay, let last = EventService.lastDay(of: event) {
                return "\(startDay) bis \(last.formatted(.dateTime.weekday(.abbreviated).day().month().locale(de)))"
            }
            return "\(startDay) bis \(end.formatted(.dateTime.weekday(.abbreviated).day().month().locale(de)))"
        }
        return startDay
    }

    private var timeText: String {
        guard let start = event.startAt, let end = event.endAt else { return "–" }
        if event.isAllDay { return "ganztägig" }
        let time = Date.FormatStyle.dateTime.hour().minute().locale(de)
        return "\(start.formatted(time)) – \(end.formatted(time)) Uhr"
    }

    private var durationText: String {
        guard let start = event.startAt, let end = event.endAt else { return "–" }
        if event.isAllDay {
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1
            return days == 1 ? "1 Tag" : "\(days) Tage"
        }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) Min."
        case (_, 0): return "\(hours) Std."
        default: return "\(hours) Std. \(rest) Min."
        }
    }

    private var assignments: [Assignment] {
        let required = RequiredRoles.decode(event.requiredRolesRaw)
        guard !required.isEmpty else { return [] }
        let participations = (event.participations as? Set<CDEventParticipation>) ?? []
        return required.map { role in
            let candidates = participations.filter {
                $0.roleRaw == role.rawValue && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined
            }
            return Assignment(role: role, who: EventService.earliest(of: candidates)?.member?.displayName)
        }
    }

    private var sourceText: String {
        let importer = ((household?.members as? Set<CDMember>) ?? [])
            .first { $0.id == event.createdByMemberID }?.displayName
        let who = importer.map { "von \($0) " } ?? ""
        return "Aus dem iPhone-Kalender \(who)übernommen. Geändert wird er dort; die Änderung kommt automatisch hierher."
    }
}
