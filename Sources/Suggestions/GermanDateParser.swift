import Foundation

/// Deutsche Datums- und Zeitangaben, wie sie in Elternbriefen, Aushängen und
/// WhatsApp-Nachrichten stehen, ohne KI und vollständig auf dem Gerät:
///
/// - "14.10.", "14.10.2026", "14. Oktober", "14. Okt. 2026"
/// - Zeiträume "12.–14.10.", "vom 12. bis 14. Oktober", "12.10.–14.10.2026" (ganztägig)
/// - Uhrzeiten "19:30", "19.30 Uhr", "19 Uhr", "15–16:30 Uhr", "15:00 bis 16:30"
/// - Wochentag mit Uhrzeit ohne Datum: "Dienstag 19 Uhr" → nächster Dienstag
///
/// Fehlt die Jahreszahl, gilt das nächste passende Datum ab gestern.
/// Ergebnis sind Vorschläge; übernommen wird nur nach Bestätigung (CLAUDE.md Regel 4).
enum GermanDateParser {

    struct Found: Equatable {
        /// 0 Uhr des (ersten) Tages
        var day: Date
        /// Letzter Tag bei Zeiträumen (einschließlich), sonst nil
        var lastDay: Date?
        var start: (hour: Int, minute: Int)?
        var end: (hour: Int, minute: Int)?

        static func == (a: Found, b: Found) -> Bool {
            a.day == b.day && a.lastDay == b.lastDay
                && a.start?.hour == b.start?.hour && a.start?.minute == b.start?.minute
                && a.end?.hour == b.end?.hour && a.end?.minute == b.end?.minute
        }
    }

    struct LineResult {
        var found: [Found]
        /// Zeile ohne Datums-, Zeit- und Füllwörter: Kandidat für den Titel.
        var rest: String
    }

    // MARK: - Muster

    private static let months: [(pattern: String, number: Int)] = [
        ("januar|jan", 1), ("februar|feb", 2), ("märz|maerz|mär|mrz", 3), ("april|apr", 4),
        ("mai", 5), ("juni|jun", 6), ("juli|jul", 7), ("august|aug", 8),
        ("september|sept|sep", 9), ("oktober|okt", 10), ("november|nov", 11), ("dezember|dez", 12)
    ]
    private static var monthAlternatives: String { months.map(\.pattern).joined(separator: "|") }

    private static let weekdays = ["sonntag", "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag"]

    private static let dash = "(?:-|–|—|bis)"

    /// Zeitraum mit Zahlen: "12.–14.10.", "12.10.–14.10.2026", "vom 12. bis 14.10."
    private static let numericRange = regex(#"(?<![\d.])(\d{1,2})\.(?:(\d{1,2})\.)?\s*\#(dash)\s*(\d{1,2})\.(\d{1,2})\.(\d{2,4})?"#)
    /// Zeitraum mit Monatsnamen: "12.–14. Oktober", "vom 12. bis 14. Okt. 2026"
    private static var namedRange: NSRegularExpression {
        regex(#"(?<![\d.])(\d{1,2})\.\s*\#(dash)\s*(\d{1,2})\.\s*(\#(monthAlternatives))\.?(?:\s+(\d{4}))?"#)
    }
    /// "14.10." / "14.10.2026" / "14. 10. 26"
    /// Zweistelliges Jahr nur direkt angehängt ("14.10.26"), sonst wäre "14.10. 19:30" das Jahr 2019.
    private static let numericDate = regex(#"(?<![\d.])(\d{1,2})\.\s?(\d{1,2})\.(?:\s?(\d{4})(?!\d)|(\d{2})(?![\d:.]))?"#)
    /// "14. Oktober" / "14. Okt. 2026"
    private static var namedDate: NSRegularExpression {
        regex(#"(?<![\d.])(\d{1,2})\.\s*(\#(monthAlternatives))\.?(?:\s+(\d{4}))?"#)
    }
    /// "15–16:30 Uhr", "15:00 bis 16:30", "15.00-16.30 Uhr"
    private static let timeRange = regex(#"(?<![\d.:])(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr\s*)?\#(dash)\s*(\d{1,2})(?:[:.](\d{2}))?\s*(uhr)?"#)
    /// "19:30", "19:30 Uhr"
    private static let colonTime = regex(#"(?<![\d.:])(\d{1,2}):(\d{2})(?![\d])"#)
    /// "19 Uhr", "19.30 Uhr"
    private static let uhrTime = regex(#"(?<![\d.:])(\d{1,2})(?:\.(\d{2}))?\s*uhr"#)
    private static var weekday: NSRegularExpression {
        regex(#"\b(\#(weekdays.joined(separator: "|")))s?\b"#)
    }
    /// Reste wie " , , " nach dem Entfernen von Datum und Uhrzeit.
    private static let separators = regex(#"\s*[,;](?:\s*[,;:])*\s*"#)
    /// Füllwörter, die ohne Datum keinen Sinn mehr ergeben.
    private static let fillers = regex(#"\b(am|ab|um|bis|vom|von|den|uhr|ca\.?|jeweils)\b"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Muster sind fest im Code; ein Fehler fiele im ersten Test auf.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // MARK: - Auswerten

    static func parse(line: String, now: Date, calendar: Calendar = .current) -> LineResult {
        var text = line as NSString
        var found: [Found] = []

        func blank(_ range: NSRange) {
            text = text.replacingCharacters(in: range, with: String(repeating: " ", count: range.length)) as NSString
        }
        func int(_ match: NSTextCheckingResult, _ group: Int) -> Int? {
            let r = match.range(at: group)
            guard r.location != NSNotFound else { return nil }
            return Int(text.substring(with: r))
        }
        func string(_ match: NSTextCheckingResult, _ group: Int) -> String? {
            let r = match.range(at: group)
            guard r.location != NSNotFound else { return nil }
            return text.substring(with: r)
        }

        // 1. Zeiträume (vor Einzeldaten, sonst würde "14.10." allein gefunden)
        for match in numericRange.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            guard let d1 = int(match, 1), let d2 = int(match, 3), let m2 = int(match, 4) else { continue }
            let m1 = int(match, 2) ?? m2
            let year = int(match, 5)
            if let first = date(day: d1, month: m1, year: year, now: now, calendar: calendar),
               let last = date(day: d2, month: m2, year: year ?? calendar.component(.year, from: first), now: first, calendar: calendar),
               last > first, calendar.dateComponents([.day], from: first, to: last).day ?? 99 <= 31 {
                found.append(Found(day: first, lastDay: last))
            }
            blank(match.range)
        }
        for match in namedRange.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            guard let d1 = int(match, 1), let d2 = int(match, 2), let name = string(match, 3),
                  let month = monthNumber(name) else { continue }
            let year = int(match, 4)
            if let first = date(day: d1, month: month, year: year, now: now, calendar: calendar),
               let last = date(day: d2, month: month, year: calendar.component(.year, from: first), now: first, calendar: calendar),
               last > first {
                found.append(Found(day: first, lastDay: last))
            }
            blank(match.range)
        }

        // 2. Einzelne Daten
        for match in namedDate.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            guard let d = int(match, 1), let name = string(match, 2), let month = monthNumber(name) else { continue }
            if let day = date(day: d, month: month, year: int(match, 3), now: now, calendar: calendar) {
                found.append(Found(day: day))
            }
            blank(match.range)
        }
        for match in numericDate.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            guard let d = int(match, 1), let m = int(match, 2), (1...12).contains(m) else { continue }
            if let day = date(day: d, month: m, year: int(match, 3) ?? int(match, 4), now: now, calendar: calendar) {
                found.append(Found(day: day))
                blank(match.range)
            }
        }

        // 3. Uhrzeiten (nach den Daten, damit "12.–14.10." keine Uhrzeit wird)
        var start: (Int, Int)?
        var end: (Int, Int)?
        if let match = timeRange.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)),
           let h1 = int(match, 1), let h2 = int(match, 3) {
            let m1 = int(match, 2), m2 = int(match, 4)
            let hasUhr = string(match, 5) != nil
            // Ohne Minuten auf beiden Seiten nur mit "Uhr" (sonst wäre "3-4" eine Uhrzeit).
            if (m1 != nil || m2 != nil || hasUhr), valid(h1, m1 ?? 0), valid(h2, m2 ?? 0) {
                start = (h1, m1 ?? 0)
                end = (h2, m2 ?? 0)
                blank(match.range)
            }
        }
        if start == nil,
           let match = colonTime.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))
            ?? uhrTime.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)),
           let h = int(match, 1), valid(h, int(match, 2) ?? 0) {
            start = (h, int(match, 2) ?? 0)
            blank(match.range)
        }

        // 4. Wochentag ohne Datum, aber mit Uhrzeit: nächster solcher Tag
        var weekdayMatches = weekday.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        if found.isEmpty, start != nil, let match = weekdayMatches.first,
           let name = string(match, 1)?.lowercased(),
           let index = weekdays.firstIndex(where: { name.hasPrefix($0) }) {
            let today = calendar.startOfDay(for: now)
            let next = calendar.nextDate(after: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                                         matching: DateComponents(weekday: index + 1),
                                         matchingPolicy: .nextTime)
            if let next { found.append(Found(day: calendar.startOfDay(for: next))) }
        }
        // Wochentage aus dem Titel entfernen ("Dienstag, 14.10." → nur Datum)
        weekdayMatches = weekday.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in weekdayMatches.reversed() { blank(match.range) }

        // Uhrzeit gilt für alle eintägigen Daten der Zeile
        found = found.map { item in
            guard item.lastDay == nil else { return item }
            var copy = item
            copy.start = start.map { (hour: $0.0, minute: $0.1) }
            copy.end = end.map { (hour: $0.0, minute: $0.1) }
            return copy
        }

        // Titel: Füllwörter und Satzzeichen weg, Leerraum zusammenfassen
        var rest = fillers.stringByReplacingMatches(in: text as String, range: NSRange(location: 0, length: text.length),
                                                    withTemplate: " ")
        rest = rest.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " :-–,.;()/").union(.whitespaces))
        rest = separators.stringByReplacingMatches(in: rest, range: NSRange(rest.startIndex..., in: rest),
                                                   withTemplate: ", ")
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " :-–,.;()/").union(.whitespaces))
        return LineResult(found: found, rest: rest)
    }

    // MARK: - Hilfen

    private static func valid(_ hour: Int, _ minute: Int) -> Bool {
        (0..<24).contains(hour) && (0..<60).contains(minute)
    }

    private static func monthNumber(_ name: String) -> Int? {
        let lower = name.lowercased()
        return months.first { entry in
            entry.pattern.split(separator: "|").contains { lower == $0 }
        }?.number
    }

    /// Datum; ohne Jahr das nächste ab gestern. Zweistellige Jahre gelten als 20xx.
    private static func date(day: Int, month: Int, year: Int?, now: Date, calendar: Calendar) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        if let year {
            let full = year < 100 ? 2000 + year : year
            guard let date = calendar.date(from: DateComponents(year: full, month: month, day: day)),
                  calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        let thisYear = calendar.component(.year, from: now)
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        for candidate in [thisYear, thisYear + 1] {
            if let date = calendar.date(from: DateComponents(year: candidate, month: month, day: day)),
               calendar.component(.day, from: date) == day, date >= yesterday {
                return date
            }
        }
        return nil
    }
}
