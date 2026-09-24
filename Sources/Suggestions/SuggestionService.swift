import CoreData
import UIKit

/// Speichert Vorschläge aus Fotos und macht daraus – nur nach Bestätigung – Termine.
///
/// Ein `CDSuggestionDraft` je Foto. Die einzelnen Vorschläge stehen als JSON in
/// `extractedPayload`, jeder mit eigener Entscheidung. Das Foto bleibt verkleinert in
/// `sourceAsset`, damit die Bestätigung nachprüfbar ist (CLAUDE.md Regel 4).
enum SuggestionService {

    static func pendingRequest() -> NSFetchRequest<CDSuggestionDraft> {
        let request = NSFetchRequest<CDSuggestionDraft>(entityName: "CDSuggestionDraft")
        request.predicate = NSPredicate(format: "statusRaw == %@", SuggestionStatus.pending.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return request
    }

    @discardableResult
    static func saveDraft(image: UIImage,
                          result: SuggestionExtractor.Result,
                          household: CDHousehold,
                          author: CDMember,
                          in context: NSManagedObjectContext) -> CDSuggestionDraft {
        let now = Date()
        let draft = CDSuggestionDraft(context: context)
        PersistenceController.assign(draft, toStoreOf: household)
        draft.id = UUID()
        draft.household = household
        draft.sourceKindRaw = SuggestionSourceKind.photo.rawValue
        draft.sourceAsset = downscaledJPEG(image)
        draft.sourceTextExcerpt = String(result.recognizedText.prefix(2000))
        draft.extractedPayload = try? JSONEncoder().encode(result.suggestions)
        draft.statusRaw = result.suggestions.isEmpty
            ? SuggestionStatus.rejected.rawValue
            : SuggestionStatus.pending.rawValue
        draft.createdByMemberID = author.id
        draft.createdAt = now
        draft.updatedAt = now
        PersistenceController.shared.save(context)
        return draft
    }

    static func suggestions(of draft: CDSuggestionDraft) -> [SuggestedEvent] {
        guard let data = draft.extractedPayload else { return [] }
        return (try? JSONDecoder().decode([SuggestedEvent].self, from: data)) ?? []
    }

    /// Der einzige Weg von einem Vorschlag zu einem Termin: ausdrückliche Bestätigung
    /// durch einen Erwachsenen (Regel 4).
    static func accept(_ suggestion: SuggestedEvent,
                       subjects: [CDMember],
                       in draft: CDSuggestionDraft,
                       by adult: CDMember,
                       context: NSManagedObjectContext) {
        guard adult.role == .adult, let household = draft.household else { return }
        let event = EventService.makeEvent(in: context, household: household,
                                           title: suggestion.title,
                                           startAt: suggestion.start, endAt: suggestion.end,
                                           createdBy: adult, subjects: subjects,
                                           locationName: suggestion.location)
        event.originRaw = EventOrigin.fromSuggestion.rawValue
        var updated = suggestion
        updated.decision = .accepted
        updated.resultingEventID = event.id
        record(updated, in: draft, by: adult)
        if draft.resultingEventID == nil { draft.resultingEventID = event.id }
        PersistenceController.shared.save(context)
    }

    static func reject(_ suggestion: SuggestedEvent,
                       in draft: CDSuggestionDraft,
                       by adult: CDMember,
                       context: NSManagedObjectContext) {
        var updated = suggestion
        updated.decision = .rejected
        record(updated, in: draft, by: adult)
        PersistenceController.shared.save(context)
    }

    /// Alle offenen Vorschläge eines Fotos auf einmal verwerfen.
    static func discard(_ draft: CDSuggestionDraft, by adult: CDMember, context: NSManagedObjectContext) {
        draft.statusRaw = SuggestionStatus.rejected.rawValue
        draft.reviewedAt = Date()
        draft.reviewedByMemberID = adult.id
        draft.updatedAt = Date()
        PersistenceController.shared.save(context)
    }

    // MARK: - Intern

    private static func record(_ suggestion: SuggestedEvent, in draft: CDSuggestionDraft, by adult: CDMember) {
        var all = suggestions(of: draft)
        if let index = all.firstIndex(where: { $0.id == suggestion.id }) {
            all[index] = suggestion
        }
        draft.extractedPayload = try? JSONEncoder().encode(all)
        draft.reviewedAt = Date()
        draft.reviewedByMemberID = adult.id
        draft.updatedAt = Date()
        if all.allSatisfy({ $0.decision != nil }) {
            draft.statusRaw = all.contains { $0.decision == .accepted }
                ? SuggestionStatus.accepted.rawValue
                : SuggestionStatus.rejected.rawValue
        }
    }

    private static func downscaledJPEG(_ image: UIImage, maxSide: CGFloat = 1600) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }
}
