import CoreData
import Foundation

/// "Übernehme ich" von außerhalb der Oberfläche: aus einer Mitteilung (Vorabend-Abfrage)
/// oder von der Apple Watch. Gespeichert wird immer über die Service-Funktionen (Regel 5).
@MainActor
enum ClaimActions {

    enum Scope { case single, series }

    enum Outcome: Equatable {
        case claimed(count: Int)
        case alreadyTaken(by: String)
        case notPossible(String)

        var message: String {
            switch self {
            case .claimed(let count): return count > 1 ? "Übernommen (\(count) Termine)" : "Übernommen"
            case .alreadyTaken(let name): return "Schon vergeben an \(name)"
            case .notPossible(let reason): return reason
            }
        }
    }

    static func claim(eventID: UUID, role: ParticipationRole, scope: Scope,
                      persistence: PersistenceController = .shared) -> Outcome {
        let context = persistence.viewContext
        guard let household = try? HouseholdService.fetchHousehold(in: context, persistence: persistence),
              let me = CurrentMember.resolve(in: context, household: household), me.role == .adult
        else { return .notPossible("Nur Erwachsene können übernehmen") }
        let request = NSFetchRequest<CDEvent>(entityName: "CDEvent")
        request.predicate = NSPredicate(format: "id == %@ AND deletedAt == nil", eventID as CVarArg)
        request.fetchLimit = 1
        guard let event = try? context.fetch(request).first else { return .notPossible("Termin nicht gefunden") }

        let outcome: Outcome
        if scope == .series && SeriesService.isSeries(event) {
            let count = SeriesService.claimFollowing(role: role, from: event, by: me, in: context)
            let others = ((event.participations as? Set<CDEventParticipation>) ?? []).filter {
                $0.roleRaw == role.rawValue && $0.member?.objectID != me.objectID
                    && ParticipationStatus(rawValue: $0.statusRaw ?? "") != .declined
            }
            if count == 0, let winner = EventService.earliest(of: others) {
                outcome = .alreadyTaken(by: winner.member?.displayName ?? "jemand anderem")
            } else {
                outcome = .claimed(count: max(count, 1))
            }
        } else {
            switch EventService.claim(role: role, on: event, by: me, in: context) {
            case .claimed: outcome = .claimed(count: 1)
            case .alreadyTaken(let name): outcome = .alreadyTaken(by: name)
            }
        }
        persistence.save(context)
        NotificationCenter.default.post(name: .remindersNeedReschedule, object: nil)
        return outcome
    }
}
