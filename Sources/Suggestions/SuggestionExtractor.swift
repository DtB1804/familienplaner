import Foundation
import Vision
import CoreGraphics
import FoundationModels
import os

/// Ein aus einem Foto erkannter Terminvorschlag. Noch kein Termin (CLAUDE.md Regel 4).
struct SuggestedEvent: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var location: String?
    /// true, wenn keine Uhrzeit erkannt wurde und die App eine angenommen hat.
    var timeIsGuessed: Bool
    /// Entscheidung eines Erwachsenen: nil = offen, sonst accepted/rejected.
    var decision: SuggestionStatus? = nil
    var resultingEventID: UUID? = nil
}

extension SuggestionStatus: Codable {}

/// Foto → Text (Vision, auf dem Gerät) → Terminvorschläge.
///
/// Zwei Wege (CLAUDE.md Regel 10):
/// 1. Apple Intelligence verfügbar: Das Sprachmodell auf dem Gerät liest den Text und
///    liefert strukturierte Vorschläge (Guided Generation).
/// 2. Nicht verfügbar oder fehlgeschlagen: Datumserkennung mit `NSDataDetector` Zeile
///    für Zeile. Einfacher, aber ohne KI.
/// Beides läuft vollständig auf dem iPhone.
enum SuggestionExtractor {

    enum Method: String { case onDeviceModel, dateDetector }

    struct Result {
        var recognizedText: String
        var suggestions: [SuggestedEvent]
        var method: Method
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                       category: "Suggestions")

    static var modelIsAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func extract(from image: CGImage, now: Date = Date()) async throws -> Result {
        let text = try await recognizeText(in: image)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Result(recognizedText: "", suggestions: [], method: .dateDetector)
        }
        if modelIsAvailable {
            do {
                let suggestions = try await extractWithModel(text: text, now: now)
                if !suggestions.isEmpty {
                    return Result(recognizedText: text, suggestions: suggestions, method: .onDeviceModel)
                }
            } catch {
                logger.error("Sprachmodell fehlgeschlagen, nutze Datumserkennung: \(error.localizedDescription, privacy: .public)")
            }
        }
        return Result(recognizedText: text,
                      suggestions: extractWithDetector(text: text, now: now),
                      method: .dateDetector)
    }

    // MARK: - Texterkennung

    static func recognizeText(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE")]
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - Weg 1: Sprachmodell auf dem Gerät

    @Generable(description: "Termine aus einem Elternbrief, Aushang oder Screenshot")
    struct ModelOutput {
        @Guide(description: "Alle konkreten Termine im Text. Leer, wenn keiner vorkommt.")
        var events: [ModelEvent]
    }

    @Generable(description: "Ein einzelner Termin")
    struct ModelEvent {
        @Guide(description: "Kurzer Titel auf Deutsch, höchstens fünf Wörter")
        var title: String
        @Guide(description: "Datum im Format JJJJ-MM-TT")
        var date: String
        @Guide(description: "Beginn im Format HH:MM, leer wenn keine Uhrzeit genannt ist")
        var startTime: String
        @Guide(description: "Ende im Format HH:MM, leer wenn nicht genannt")
        var endTime: String
        @Guide(description: "Ort, leer wenn nicht genannt")
        var location: String
    }

    private static func extractWithModel(text: String, now: Date) async throws -> [SuggestedEvent] {
        let today = dayFormatter.string(from: now)
        let session = LanguageModelSession(instructions: """
            Du liest Texte aus Elternbriefen, Schulaushängen und Screenshots und findest darin Termine.
            Heute ist der \(today). Fehlt eine Jahreszahl, nimm das nächste passende Datum ab heute.
            Erfinde nichts: Nur Termine, die im Text stehen.
            """)
        let response = try await session.respond(
            to: "Finde alle Termine in diesem Text:\n\n\(text.prefix(3500))",
            generating: ModelOutput.self)

        return response.content.events.compactMap { item in
            guard let day = dayFormatter.date(from: item.date.trimmingCharacters(in: .whitespaces)) else {
                return nil
            }
            let start = combine(day, item.startTime)
            let end = combine(day, item.endTime).flatMap { $0 > (start ?? day) ? $0 : nil }
            let guessed = start == nil
            let begin = start ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return SuggestedEvent(title: title.isEmpty ? "Termin" : title,
                                  start: begin,
                                  end: end ?? begin.addingTimeInterval(3600),
                                  location: item.location.isEmpty ? nil : item.location,
                                  timeIsGuessed: guessed)
        }
    }

    // MARK: - Weg 2: ohne KI

    static func extractWithDetector(text: String, now: Date) -> [SuggestedEvent] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }
        let calendar = Calendar.current
        var result: [SuggestedEvent] = []
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            for match in detector.matches(in: line, options: [], range: range) {
                guard let date = match.date,
                      date > calendar.date(byAdding: .day, value: -1, to: now) ?? now else { continue }
                var title = line
                if let r = Range(match.range, in: line) { title.removeSubrange(r) }
                title = title.trimmingCharacters(in: CharacterSet(charactersIn: " :-–,.;").union(.whitespaces))
                let hasTime = calendar.component(.hour, from: date) != 12
                    || calendar.component(.minute, from: date) != 0
                let start = hasTime
                    ? date
                    : calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
                let duration = match.duration > 0 ? match.duration : 3600
                result.append(SuggestedEvent(title: title.isEmpty ? "Termin" : String(title.prefix(60)),
                                             start: start,
                                             end: start.addingTimeInterval(duration),
                                             location: nil,
                                             timeIsGuessed: !hasTime))
            }
        }
        return result
    }

    // MARK: - Hilfen

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func combine(_ day: Date, _ time: String) -> Date? {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
