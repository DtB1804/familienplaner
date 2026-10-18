import SwiftUI

/// Kurzanleitung zu den wichtigsten Funktionen. Aufruf über das Ansicht-Menü rechts neben den Namen
/// (Tag/Woche/Monat → "Kurzanleitung"). Nur Text, keine Daten: Gilt für alle gleich.
/// Bei neuen Funktionen hier mitpflegen (CLAUDE.md Regel 20).
struct HelpScreen: View {

    @Environment(\.dismiss) private var dismiss

    private struct HelpTopic: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let points: [String]
    }

    private struct HelpGroup: Identifiable {
        let id = UUID()
        let title: String
        let topics: [HelpTopic]
    }

    private let groups: [HelpGroup] = [
        HelpGroup(title: "Ansehen", topics: [
            HelpTopic(symbol: "calendar.day.timeline.left", title: "Tag, Woche, Monat", points: [
                "Symbol rechts neben den Namen: Ansicht wechseln, vergrößern, verkleinern und diese Kurzanleitung.",
                "In der Tagesansicht hat jede Person eine eigene Spalte. Seitlich wischen blättert einen Tag weiter.",
                "Datum oben antippen: Tag auswählen. „Heute“ springt zurück.",
                "In der Woche öffnet ein Tipp auf den Tageskopf diesen Tag."
            ]),
            HelpTopic(symbol: "person.2", title: "Personen ein- und ausblenden", points: [
                "Die Namen in der Leiste oben antippen, um Personen aus- oder wieder einzublenden."
            ]),
            HelpTopic(symbol: "magnifyingglass", title: "Suche", points: [
                "Unten „Suche“: Termine nach Titel finden."
            ])
        ]),
        HelpGroup(title: "Termine", topics: [
            HelpTopic(symbol: "plus", title: "Neuer Termin", points: [
                "Unten „Neu“. Für wen, wann, wiederholen und wer bringt oder holt.",
                "Bei Serien fragt die App beim Ändern: nur dieser Termin oder auch alle folgenden."
            ]),
            HelpTopic(symbol: "hand.draw", title: "Verschieben", points: [
                "Termin gedrückt halten und ziehen: hoch und runter ändert die Uhrzeit.",
                "Seitlich in eine andere Spalte: Der Termin gilt dann für diese Person.",
                "Nach dem Verschieben erscheint unten „Rückgängig“."
            ]),
            HelpTopic(symbol: "camera", title: "Foto oder Text", points: [
                "Unten „Foto oder Text“: Elternbrief fotografieren, Bildschirmfoto wählen oder kopierten Text (z. B. aus WhatsApp) einfügen.",
                "Auch über den Teilen-Knopf in anderen Apps an Family Planner schicken.",
                "Erkannte Termine werden erst nach deiner Bestätigung eingetragen."
            ]),
            HelpTopic(symbol: "calendar.badge.clock", title: "Freie Zeit finden", points: [
                "Unten „Freie Zeit“: Personen wählen und gemeinsame freie Zeiten anzeigen. Tippen legt dort einen Termin an."
            ])
        ]),
        HelpGroup(title: "Bringen und Holen", topics: [
            HelpTopic(symbol: "questionmark.circle", title: "Offene Aufgaben", points: [
                "„Holt ?“ oder „Bringt ?“ am Termin: Das hat noch niemand übernommen.",
                "Termin antippen → „Übernehme ich“. Bei Serien geht das auch für die ganze Serie.",
                "Der Hinweis oben in der Tagesansicht sammelt alle offenen Aufgaben der nächsten 14 Tage."
            ]),
            HelpTopic(symbol: "bell", title: "Nachfragen per Mitteilung", points: [
                "Unter Familie → Erinnerungen: vor eigenen Terminen erinnern, am Vorabend nachfragen, neue offene Aufgaben sofort melden.",
                "Übernehmen geht direkt aus der Mitteilung."
            ])
        ]),
        HelpGroup(title: "Eigene Kalender", topics: [
            HelpTopic(symbol: "calendar", title: "Termine aus dem iPhone-Kalender", points: [
                "Unter Familie → Meine Kalender je Kalender wählen: nicht zeigen, nur als „Belegt“ oder mit Titel.",
                "Übernommene Termine ändert man in der Kalender-App. Im Family Planner bleiben sie damit verknüpft.",
                "Ein „?“ heißt: Noch offen, ob jemand bringen oder holen muss. Antippen und beantworten, auch „Nicht nötig“.",
                "In eine andere Spalte ziehen, wenn der Termin für jemand anderen ist, z. B. „Tennis“ aus Mamas Kalender zum Kind."
            ]),
            HelpTopic(symbol: "calendar.badge.plus", title: "Familientermine im iPhone-Kalender", points: [
                "Unter Familie → Meine Kalender lassen sich die Familientermine in einen eigenen Kalender „Family Planner“ eintragen."
            ])
        ]),
        HelpGroup(title: "Familie", topics: [
            HelpTopic(symbol: "person.badge.plus", title: "Mitglieder und Einladen", points: [
                "Unter Familie Personen anlegen. Einladen muss man nur, wer ein eigenes iPhone hat.",
                "Wer eingeladen wird, braucht vorher Family Planner auf dem iPhone."
            ]),
            HelpTopic(symbol: "eye", title: "Kinderansicht", points: [
                "Unter Familie einstellen, ob Kinder die Termine der Erwachsenen mit Titel oder nur als „Belegt“ sehen.",
                "„Als … ansehen“ zeigt die App so, wie das Kind sie sieht."
            ]),
            HelpTopic(symbol: "square.and.arrow.up", title: "Sicherung", points: [
                "Unter Familie → „Alle Termine exportieren“: eine Kalenderdatei als Rückfallebene."
            ])
        ]),
        HelpGroup(title: "Außerhalb der App", topics: [
            HelpTopic(symbol: "square.grid.2x2", title: "Widgets und Apple Watch", points: [
                "Widgets für den Home- und Sperrbildschirm zeigen die nächsten Termine und offene Aufgaben.",
                "Auf der Apple Watch: eigene Termine ansehen und offene Aufgaben übernehmen."
            ])
        ])
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.topics) { topic in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(topic.points, id: \.self) { point in
                                        Text("• " + point)
                                            .font(.subheadline)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.vertical, 2)
                            } label: {
                                Label(topic.title, systemImage: topic.symbol)
                            }
                            .accessibilityIdentifier("help.\(topic.title)")
                        }
                    }
                }
            }
            .navigationTitle("Kurzanleitung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("help.done")
                }
            }
        }
    }
}
