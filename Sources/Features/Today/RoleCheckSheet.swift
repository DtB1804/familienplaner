import SwiftUI
import CoreData

/// Abfrage für Termine aus dem iPhone-Kalender: Muss jemand bringen oder holen?
/// Bis jemand antwortet, trägt der Termin ein "?" (CLAUDE.md Regel 21).
/// Die Antwort schreibt nur `requiredRolesRaw`; übernommen wird danach wie gewohnt
/// über "Offene Zuständigkeiten" (Regel 5).
struct RoleCheckSheet: View {

    let me: CDMember?
    let household: CDHousehold?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var items: [CDEvent] = []
    /// Termin, für den gerade die Auswahl offen ist.
    @State private var pending: CDEvent?
    /// Nach einer Antwort: dieselbe Antwort für weitere Vorkommen derselben Kalenderserie?
    @State private var seriesOffer: SeriesOffer?

    private struct SeriesOffer: Identifiable {
        let id = UUID()
        let title: String
        let roles: [ParticipationRole]
        let siblings: [CDEvent]
    }

    private let de = Locale(identifier: "de_DE")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items, id: \.objectID) { event in
                        Button { pending = event } label: { row(event) }
                            .accessibilityIdentifier("roleCheck.\(title(of: event))")
                    }
                } footer: {
                    if !items.isEmpty {
                        Text("Termine aus euren iPhone-Kalendern. Titel und Zeit kommen aus dem Kalender, ob jemand bringt oder holt, legt ihr hier fest.")
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Alles geklärt",
                                           systemImage: "checkmark.circle",
                                           description: Text("Für die nächsten 14 Tage ist bei allen Terminen aus dem Kalender klar, ob jemand bringt oder holt."))
                }
            }
            .navigationTitle("Bringen oder Holen?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("roleCheck.done")
                }
            }
            .confirmationDialog(pending.map { title(of: $0) } ?? "",
                                isPresented: Binding(get: { pending != nil },
                                                     set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible) {
                if let event = pending {
                    ForEach(RoleCheckChoice.allCases) { choice in
                        Button(choice.label) { answer(event, roles: choice.roles) }
                            .accessibilityIdentifier("roleCheck.choice.\(choice.rawValue)")
                    }
                }
            } message: {
                Text("Muss jemand bringen oder holen?")
            }
            .alert("Auch für die anderen Termine?",
                   isPresented: Binding(get: { seriesOffer != nil },
                                        set: { if !$0 { seriesOffer = nil } })) {
                if let offer = seriesOffer {
                    Button("Ja, für alle \(offer.siblings.count + 1)") { applyToSiblings(offer) }
                        .accessibilityIdentifier("roleCheck.series.yes")
                    Button("Nur dieser Termin", role: .cancel) { seriesOffer = nil }
                }
            } message: {
                if let offer = seriesOffer {
                    Text("„\(offer.title)“ wiederholt sich im Kalender. Weitere \(offer.siblings.count) Termine sind noch ungeklärt. Spätere Termine dieser Serie übernehmen die Antwort automatisch.")
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func row(_ event: CDEvent) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(of: event))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail(of: event))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("?")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 6)
                .background(Palette.color("person5"), in: Capsule())
                .foregroundStyle(.black)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Festlegen, ob jemand bringen oder holen muss")
    }

    private func title(of event: CDEvent) -> String {
        EventPresentation.title(of: event, for: me, in: household)
    }

    private func detail(of event: CDEvent) -> String {
        var parts: [String] = []
        if let start = event.startAt {
            parts.append(start.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(de)))
        }
        let names = EventService.subjects(of: event).compactMap(\.displayName)
        if !names.isEmpty { parts.append("Kalender von " + names.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func answer(_ event: CDEvent, roles: [ParticipationRole]) {
        pending = nil
        EventService.answerRoleCheck(event, roles: roles)
        PersistenceController.shared.save(context)
        let siblings = EventService.pendingSeriesSiblings(of: event, in: context)
        if !siblings.isEmpty {
            seriesOffer = SeriesOffer(title: title(of: event), roles: roles, siblings: siblings)
        }
        reload()
    }

    private func applyToSiblings(_ offer: SeriesOffer) {
        for sibling in offer.siblings { EventService.answerRoleCheck(sibling, roles: offer.roles) }
        PersistenceController.shared.save(context)
        seriesOffer = nil
        reload()
    }

    private func reload() {
        items = EventService.pendingRoleChecks(in: context)
    }
}

/// Antworten auf "Muss jemand bringen oder holen?" – in der Liste, im Termin und in der Mitteilung.
enum RoleCheckChoice: String, CaseIterable, Identifiable {
    case both, driveTo, driveFrom, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both: return "Bringen und Holen"
        case .driveTo: return "Nur Bringen"
        case .driveFrom: return "Nur Holen"
        case .none: return "Nicht nötig"
        }
    }

    var roles: [ParticipationRole] {
        switch self {
        case .both: return [.driveTo, .driveFrom]
        case .driveTo: return [.driveTo]
        case .driveFrom: return [.driveFrom]
        case .none: return []
        }
    }
}
