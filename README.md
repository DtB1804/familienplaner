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

## Backlog (Stand 25.09.2026)

| Thema | Stand | Notiz |
|---|---|---|
| Termine aus Fotos | Grundfunktion da (Build 8) | **Nicht vergessen (David):** Qualität mit echten Elternbriefen weiter testen und nachschärfen, Kamera direkt aus der App, ggf. Teilen-Erweiterung aus Fotos/Mail |
| Ganztägige Termine | offen | Leiste über dem Zeitstrahl, auch aus iPhone-Kalendern |
| Erinnerungen | da (Build 12, Hintergrund ab Build 18) | lokal je Gerät, Neuplanung auch bei Änderungen anderer |
| iPad | da (Build 12) | gleiche Oberfläche, alle Ausrichtungen |
| Wiederkehrende Termine | offen | Feld im Modell vorhanden, Eingabe fehlt |
| Freiraum-Finder | offen | |
| Hintergrundabgleich (Kalender, Erinnerungen) | da (Build 18) | stille CloudKit-Mitteilungen + BGAppRefresh; Zeitpunkt bestimmt iOS |
| Familientermine in iPhone-Kalender zurückschreiben | offen | Option im Modell angelegt |
| Widgets | offen | |
| Apple-Watch-App | offen, nach Hintergrundabgleich | Heute-Übersicht, Zifferblatt-Element (nächster Termin / offene Zuständigkeit), „Übernehme ich“; Daten per WatchConnectivity vom iPhone. Erinnerungen kommen schon heute auf die Watch (iPhone gesperrt). |
| Termin in andere Personenspalte ziehen | offen | bisher nur zeitlich verschieben |
| Einladungstest mit Jana | wartet auf Jana | Aufgabe 16 |
| Kinderansicht mit Josh testen | wartet auf Josh-Gerät | |

## Bekannte offene Punkte

- Ob ein Kinderaccount unter 13 aus einer Familienfreigabe eine CKShare-Einladung
  annehmen kann, ist nicht belegt. Dafür gibt es `MemberAccountKind.managed` als
  zweiten Pfad. Der Test steht als Aufgabe 6 in `AUFGABEN-DAVID.md`.
- Anzeigename auf dem Homescreen: "Family Planner". Technischer Name bleibt `Familienplaner`.
- Die Bundle-ID `de.barg.familienplaner` ist ein Vorschlag und an vier Stellen
  hinterlegt: `project.yml`, `Resources/Info.plist` (BGTaskScheduler),
  `Resources/Familienplaner.entitlements` und `PersistenceController.swift`.
  Beim Ändern alle vier anpassen.
