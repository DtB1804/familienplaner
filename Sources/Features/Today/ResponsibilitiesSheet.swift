import SwiftUI
import CoreData

/// Offene Zuständigkeiten (Bringen, Holen, Begleiten) der nächsten 14 Tage.
/// Übernehmen legt eine neue Beteiligung an (CLAUDE.md Regel 5).
///
/// Gehört der Termin zu einer Serie, fragt die App, ob die Übernahme für die ganze Serie
/// gilt. Wenn nicht, bietet sie die Nachfrage am Vorabend an (Erinnerungen).
struct ResponsibilitiesSheet: View {

    let me: CDMember?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ReminderSettings.openEnabledKey) private var eveningQuestion = false

    @State private var items: [OpenResponsibility] = []
    @State private var message: String?
    @State private var info: String?
    /// Termine in dieser Liste, die zu einer Serie gehören.
    @State private var seriesEventIDs: Set<UUID> = []
    /// Serientermin, für den gerade gefragt wird: nur dieser oder ganze Serie?
    @State private var pendingSeriesItem: OpenResponsibility?
    @State private var offerEveningQuestion = false

    private var canClaim: Bool { me?.role == .adult }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                if seriesEventIDs.contains(item.eventID) {
                                    Image(systemName: "repeat")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                Text("\(item.role.label): \(item.eventTitle)")
                            }
                            Text(item.startAt.formatted(.dateTime.weekday(.wide).day().month().hour().minute()
                                                        .locale(Locale(identifier: "de_DE"))))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if canClaim {
                            Button("Übernehme ich") {
                                if seriesEventIDs.contains(item.eventID) {
                                    pendingSeriesItem = item
                                } else {
                                    claim(item, scope: .single)
                                }
                            }
                            .accessibilityIdentifier("claim.\(item.eventTitle)")
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Alles vergeben",
                                           systemImage: "checkmark.circle",
                                           description: Text("In den nächsten 14 Tagen ist keine Zuständigkeit offen."))
                }
            }
            .navigationTitle("Offene Zuständigkeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("responsibilities.done")
                }
            }
            .confirmationDialog(seriesQuestion, isPresented: Binding(
                get: { pendingSeriesItem != nil }, set: { if !$0 { pendingSeriesItem = nil } }),
                titleVisibility: .visible) {
                if let item = pendingSeriesItem {
                    Button("Für die ganze Serie") { claim(item, scope: .series) }
                        .accessibilityIdentifier("claimScope.series")
                    Button("Nur \(item.startAt.formatted(.dateTime.weekday(.abbreviated).day().month().locale(Locale(identifier: "de_DE"))))") {
                        claim(item, scope: .single)
                        if !eveningQuestion { offerEveningQuestion = true }
                    }
                    .accessibilityIdentifier("claimScope.single")
                }
            } message: {
                Text("Bei „ganze Serie“ gilt die Übernahme auch für später ergänzte Termine. Einzelne Termine lassen sich im Termin wieder abgeben.")
            }
            .alert("Am Vorabend nachfragen?", isPresented: $offerEveningQuestion) {
                Button("Ja, nachfragen") { enableEveningQuestion() }
                    .accessibilityIdentifier("evening.enable")
                Button("Nein", role: .cancel) {}
            } message: {
                Text("Family Planner fragt dann am Abend vorher per Mitteilung, wer offene Zuständigkeiten übernimmt, z. B. „Wer holt morgen?“. Übernehmen geht direkt aus der Mitteilung.")
            }
            .alert("Schon vergeben",
                   isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .alert("Übernommen",
                   isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(info ?? "")
            }
            .onAppear(perform: reload)
        }
    }

    private var seriesQuestion: String {
        guard let item = pendingSeriesItem else { return "" }
        return "\(item.role.label) bei „\(item.eventTitle)“"
    }

    private func claim(_ item: OpenResponsibility, scope: ClaimActions.Scope) {
        switch ClaimActions.claim(eventID: item.eventID, role: item.role, scope: scope) {
        case .claimed(let count):
            if scope == .series {
                info = "\(item.role.label): „\(item.eventTitle)“ für die ganze Serie übernommen (\(count) Termine, weitere folgen automatisch)."
            }
        case .alreadyTaken(let name):
            message = "\(item.role.label) übernimmt bereits \(name)."
        case .notPossible(let reason):
            message = reason
        }
        reload()
    }

    private func enableEveningQuestion() {
        Task {
            if await ReminderService.requestAuthorization() {
                eveningQuestion = true
                NotificationCenter.default.post(name: .remindersNeedReschedule, object: nil)
            } else {
                message = "Mitteilungen sind für Family Planner ausgeschaltet. Sie lassen sich in den iPhone-Einstellungen erlauben."
            }
        }
    }

    private func event(for item: OpenResponsibility) -> CDEvent? {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "id == %@", item.eventID as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func reload() {
        items = (try? EventService.openResponsibilities(in: context)) ?? []
        seriesEventIDs = Set(items.compactMap { item in
            event(for: item).flatMap { SeriesService.isSeries($0) ? item.eventID : nil }
        })
    }
}
