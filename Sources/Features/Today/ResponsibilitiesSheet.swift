import SwiftUI
import CoreData

/// Offene Zuständigkeiten (Bringen, Holen, Begleiten) der nächsten 14 Tage.
/// Übernehmen legt eine neue Beteiligung an (CLAUDE.md Regel 5).
struct ResponsibilitiesSheet: View {

    let me: CDMember?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var items: [OpenResponsibility] = []
    @State private var message: String?
    @State private var info: String?
    /// Termine in dieser Liste, die zu einer Serie gehören.
    @State private var seriesEventIDs: Set<UUID> = []

    private var canClaim: Bool { me?.role == .adult }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.role.label): \(item.eventTitle)")
                            Text(item.startAt.formatted(.dateTime.weekday(.wide).day().month().hour().minute()
                                                        .locale(Locale(identifier: "de_DE"))))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if canClaim {
                            VStack(alignment: .trailing, spacing: 6) {
                                Button("Übernehme ich") { claim(item) }
                                    .accessibilityIdentifier("claim.\(item.eventTitle)")
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                if seriesEventIDs.contains(item.eventID) {
                                    Button("Alle folgenden") { claimSeries(item) }
                                        .accessibilityIdentifier("claimSeries.\(item.eventTitle)")
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
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

    private func event(for item: OpenResponsibility) -> CDEvent? {
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "id == %@", item.eventID as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Serie: diese Zuständigkeit für diesen und alle folgenden Termine übernehmen.
    private func claimSeries(_ item: OpenResponsibility) {
        guard let me, let event = event(for: item) else { return }
        let count = SeriesService.claimFollowing(role: item.role, from: event, by: me, in: context)
        PersistenceController.shared.save(context)
        info = "\(item.role.label): \(count) Termine „\(item.eventTitle)“ übernommen. Später ergänzte Termine der Serie erscheinen wieder als offen."
        reload()
    }

    private func claim(_ item: OpenResponsibility) {
        guard let me, let event = event(for: item) else { return }

        switch EventService.claim(role: item.role, on: event, by: me, in: context) {
        case .claimed:
            PersistenceController.shared.save(context)
        case .alreadyTaken(let name):
            message = "\(item.role.label) übernimmt bereits \(name)."
        }
        reload()
    }

    private func reload() {
        items = (try? EventService.openResponsibilities(in: context)) ?? []
        seriesEventIDs = Set(items.compactMap { item in
            event(for: item).flatMap { SeriesService.isSeries($0) ? item.eventID : nil }
        })
    }
}
