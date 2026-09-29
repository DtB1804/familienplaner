# Familienplaner

Privater Familienkalender für iPhones. SwiftUI, Core Data mit CloudKit, iOS 26.

Stand: erster Aufbau (Phase 1 und Teil von Phase 2 der Umsetzungsliste).
Der Code ist auf einem Linux-Rechner ohne Swift-Toolchain entstanden und wurde
**nicht kompiliert**. Der erste Build in Xcode ist Teil der Inbetriebnahme, nicht
ein Zeichen dafür, dass etwas schiefgelaufen ist.

## Was schon da ist

| Bereich | Stand |
|---|---|
| Core-Data-Modell mit 9 Entitäten, Konfigurationen Cloud und Local | vollständig |
| `PersistenceController` mit drei Stores (private, shared, local) | vollständig |
| Domänen-Enums, kodierte Pflichtrollen | vollständig |
| `HouseholdService`: Erststart, Mitglieder, Farbvergabe, Systemkategorien | vollständig |
| `EventService`: Tagesabfrage, offene Zuständigkeiten, Claim-Logik | vollständig |
| Design-Tokens für Hell und Dunkel, Zoomstufen | vollständig |
| Tagesansicht mit Personenspalten, Stundenraster, Jetzt-Linie, Pinch-Zoom | erster Stand |
| Personen-Chips als Filter | erster Stand |
| Erststart-Einrichtung | erster Stand |
| Beispieldaten für Previews und Simulator | vollständig |
| Teilen per CKShare, Kalenderimport, Widgets, KI | noch nicht |

## Projekt öffnen

```bash
brew install xcodegen          # einmalig
xcodegen generate
open Familienplaner.xcodeproj
```

`Familienplaner.xcodeproj` ist generiert und gehört nicht ins Repository.
Alle Projekteinstellungen stehen in `project.yml`.

### Ohne XcodeGen

Geht auch: in Xcode ein neues iOS-App-Projekt namens `Familienplaner` anlegen, die
Template-Dateien löschen, dann die Ordner `Sources` und `Resources` per Drag-and-drop
hineinziehen (Option "Create groups"). Danach in den Target-Einstellungen unter
Signing & Capabilities iCloud mit CloudKit, Push Notifications und Background Modes
aktivieren und den Container `iCloud.de.barg.familienplaner` auswählen.

## Bauen ohne Mac (GitHub Actions)

| Workflow | Auslöser | Ergebnis | Log für Claude |
|---|---|---|---|
| `Build` | Push auf `main` | Simulator-Build ohne Signierung | Branch `ci-log` |
| `TestFlight` | Push auf `testflight` | Archiv, Signierung, Upload zu TestFlight | Branch `ci-log-testflight` |
| `Tests` | nachts 2–3 Uhr, nur bei neuem Stand auf `main`; von Hand jederzeit | Python-, Unit-, Smoke- und End-to-End-Tests im Simulator, Abdeckung | Branch `ci-log-tests` |

Neue TestFlight-Version: `git push origin main:testflight`. Die Build-Nummer ist die
Laufnummer des Workflows.

## Verzeichnisse

```
Sources/
  App/              App-Einstieg, Root-Navigation
  Persistence/      Core-Data-Modell, Stack, Services
  DesignSystem/     Farben, Abstände, Typografie, Zoomstufen
  Features/
    Today/          Tagesansicht mit Personenspalten
    Members/        Personen-Chips
    Setup/          Erststart
    Debug/          Beispieldaten, nur Simulator und Previews
Resources/          Info.plist, Entitlements
```

## Verbindliche Regeln

Siehe `CLAUDE.md`. Diese Datei wird vor jeder größeren Änderung gelesen, auch von
KI-Assistenten. Sie enthält unter anderem die Begründung, warum SwiftData ausscheidet
und warum eine übernommene Zuständigkeit angelegt und nicht geändert wird.

## Nächste Schritte

1. Erster Build und Start im Simulator
2. CloudKit-Schema aus dem Modell erzeugen (siehe `AUFGABEN-DAVID.md`)
3. Teilen-Flow über `UICloudSharingController`
4. Sync-Test über zwei echte Apple-IDs
5. Kalenderimport über EventKit

## Backlog (Stand 26.09.2026)

| Thema | Stand | Notiz |
|---|---|---|
| Termine aus Fotos | Kamera und Teilen-Knopf da (Build 27, nach Aufgabe 22) | Fotos/Screenshots/PDFs aus Mail, WhatsApp, Fotos, Dateien; **offen:** Qualität mit echten Elternbriefen testen, Text teilen |
| Ganztägige Termine | da (Build 23) | Leiste über dem Zeitstrahl, mehrtägig, auch als Serie (Geburtstag jährlich), Übernahme aus und Eintrag in iPhone-Kalender |
| Erinnerungen | da (Build 12, Hintergrund ab Build 18) | lokal je Gerät, Neuplanung auch bei Änderungen anderer |
| iPad | da (Build 12) | gleiche Oberfläche, alle Ausrichtungen |
| Terminserien | da (Build 21, Übernahme/Vorabend ab Build 22) | täglich bis jährlich, 26 Wochen rollierend; Zuständigkeit für ganze Serie; Vorabend-Abfrage mit „Übernehme ich“ in der Mitteilung |
| Freiraum-Finder | da (Build 25) | gemeinsame freie Zeit ausgewählter Personen, Dauer, Tageszeit, Wochenende/Werktage; Tippen legt Termin an |
| Hintergrundabgleich (Kalender, Erinnerungen) | da (Build 18) | stille CloudKit-Mitteilungen + BGAppRefresh; Zeitpunkt bestimmt iOS |
| Familientermine in iPhone-Kalender | da (Build 22) | eigener Kalender „Family Planner“, nur in diese Richtung, je Gerät Aus/meine/alle |
| Widgets | da (Build 25) | „Nächste Termine“ (klein/mittel/groß, Sperrbildschirm) und „Offene Zuständigkeiten“; Zifferblatt-Elemente der Watch ab Build 26 (nach Aufgabe 21) |
| Apple-Watch-App | Grundfunktion da (Build 19) | Heute/Morgen/Übermorgen, offene Zuständigkeiten, „Übernehme ich“; Zifferblatt-Elemente ab Build 26 (nach Aufgabe 21) |
| Termin in andere Personenspalte ziehen | da (Build 27) | halten und seitlich ziehen; Zuständigkeiten bleiben |
| iCloud-Status sichtbar | da (Build 28) | Hinweis bei offline, abgemeldet, Speicher voll, Abgleich gestört |
| Haushalt löschen / verlassen | da (Build 28) | Familie → ganz unten |
| Sicherung (.ics) | da (Build 28) | Familie → Sicherung |
| Erste Schritte | da (Build 28) | einmal je Gerät: wer bin ich, Kalender, Erinnerungen |
| Barrierefreiheit | Build 28 | große Schrift, VoiceOver-Texte und -Aktionen; Prüfung nachts |
| UX-Korrekturen | Build 29 | Rückgängig nach Ziehen, Ziehen nur senkrecht oder seitlich, „Übernehme ich“ im Termin, Foto-Knopf, Datum wählen und „Heute“, Einladung direkt nach dem Anlegen, Löschen mit Namenseingabe |
| UX-Feinschliff | Build 30 | durchgehend „Du“, „Wer bringt?/Wer holt?“, Editor mit Wichtigem oben, Antippen zeigt Details, eine Leiste für Personen/Tag-Woche/Zoom, Personenfilter blendet aus, Zeitstrahl passt sich an frühe/späte Termine an |
| Monatsübersicht | Build 33 | Ansicht-Menü → Monat: Punkte je Person, ganztägige Termine als Balken, Tippen öffnet den Tag |
| Text teilen / einfügen | Build 34 | Teilen-Knopf nimmt Text an (z. B. WhatsApp); „Foto oder Text“ → „Kopierten Text einfügen“ |
| Bessere Erkennung ohne KI | Build 34 | deutsche Schreibweisen: 14.10., 14. Oktober, 12.–14.10. (ganztägig), 19.30 Uhr, 15–16:30 Uhr, „Dienstag 19 Uhr“; Titel aus der Zeile davor |
| Woche/Monat sofort gefüllt, kurzer Tagestitel | Build 35 | Woche und Monat zeigen Termine schon beim ersten Öffnen; „Di., 29. Sept.“ statt abgeschnittenem Wochentag; offene Zuständigkeit in schmalen Spalten als „2 ?“ unten rechts |
| Übernehmen oben in der Termin-Ansicht | Build 36 | „Noch offen“ mit „Übernehme ich“ direkt unter dem Titel; seitliches Ziehen ohne Tageswechsel-Wischen; Titel-Trefferfläche 44 pt |
| Veröffentlichung „nicht gelistet“ | Vorbereitung | Texte in APP-STORE.md, Support- und Datenschutzseite in docs/ (GitHub Pages), Aufgaben 23–26 |
| Einladungstest mit zweitem Erwachsenen | wartet auf zweites Gerät | Aufgabe 16 |
| Kinderansicht auf Kindergerät testen | wartet auf Kindergerät | |

## Bekannte offene Punkte

- Ob ein Kinderaccount unter 13 aus einer Familienfreigabe eine CKShare-Einladung
  annehmen kann, ist nicht belegt. Dafür gibt es `MemberAccountKind.managed` als
  zweiten Pfad. Der Test steht als Aufgabe 6 in `AUFGABEN-DAVID.md`.
- Anzeigename auf dem Homescreen: "Family Planner". Technischer Name bleibt `Familienplaner`.
- Die Bundle-ID `de.barg.familienplaner` ist ein Vorschlag und an vier Stellen
  hinterlegt: `project.yml`, `Resources/Info.plist` (BGTaskScheduler),
  `Resources/Familienplaner.entitlements` und `PersistenceController.swift`.
  Beim Ändern alle vier anpassen.
