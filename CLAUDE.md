# Architekturregeln – Familienplaner

Diese Datei ist verbindlich. Sie gilt für jede weitere Codeänderung, egal ob von Hand
oder mit KI-Unterstützung geschrieben. Wer eine dieser Regeln brechen will, ändert
zuerst diese Datei und begründet es.

## 1. Core Data, niemals SwiftData

Apples Developer Technical Support hat im Entwicklerforum (Thread 765776) bestätigt,
dass SwiftData das Teilen von Daten zwischen mehreren iCloud-Nutzern nicht unterstützt,
und empfiehlt für Objektgraphen mit Beziehungen `NSPersistentCloudKitContainer`.
Die Familien-App steht und fällt mit dem Teilen. Also Core Data.

Core Data und SwiftData werden nicht gemischt.

## 2. Das Projektionsprinzip

CloudKit kennt keine Berechtigungen auf Feldebene. Wer eine geteilte Zone lesen darf,
liest jedes Feld jedes Datensatzes darin.

Daraus folgt: **Was jemand nicht sehen soll, wird nicht in die geteilte Zone geschrieben.**

Ein Termin aus einem Kalender mit `visibility == .busyOnly` wird auf dem Gerät des
Eigentümers reduziert, bevor er gespeichert wird: Titel wird zu "Belegt", Notizen und
Ort entfallen. Der Originaltitel verlässt das Gerät nie. Ein Feld `istPrivat` wäre eine
Bitte an die eigene App, kein Schutz.

**Bewusste Ausnahme (Entscheidung David, 22.09.2026):** Ob Kinder die Termine der
Erwachsenen mit Titel oder nur als "Belegt" sehen, ist ein reiner **Anzeige-Schalter**.
Die Kinder sind Teilnehmer derselben Freigabe und erhalten die Titel technisch mit.
Das ist akzeptiert. Kalender, deren Inhalt das Gerät gar nicht verlassen darf
(z. B. Dienstkalender), laufen weiter über die Projektion oben.

## 3. Drei Stores, keine Beziehungen über Store-Grenzen

- `private.sqlite` – Cloud-Konfiguration, CloudKit-Scope `.private`
- `shared.sqlite` – Cloud-Konfiguration, CloudKit-Scope `.shared`
- `local.sqlite` – Local-Konfiguration, kein CloudKit

`CDCalendarSource`, `CDLocalEventMirror` und `CDDeviceRegistration` liegen im lokalen
Store und verweisen über UUID-Felder auf Cloud-Entitäten, nicht über Relationships.
Core Data kann Beziehungen nicht über Store-Grenzen auflösen. Das ist Absicht.

## 4. Kein KI-Vorschlag wird automatisch zum Termin

`CDSuggestionDraft` ist eine eigene Entität. Es gibt genau einen Weg von einem Vorschlag
zu einem Termin: eine ausdrückliche Bestätigung durch einen Erwachsenen im UI.
Kein Hintergrundjob, kein "wenn Konfidenz über 0,9", keine Ausnahme.

Der Originalausschnitt (`sourceAsset`) bleibt am Vorschlag hängen, damit die
Bestätigung nachprüfbar ist.

## 5. Zuständigkeiten werden angelegt, nicht geändert

Eine offene Zuständigkeit ist **kein Datensatz** mit leerem Mitglied, sondern die
Differenz zwischen `CDEvent.requiredRolesRaw` und den vorhandenen Beteiligungen.

Übernimmt jemand eine Zuständigkeit, wird ein **neuer** `CDEventParticipation`-Datensatz
angelegt. Grund: CloudKit löst Konflikte auf Datensatzebene nach "letzter Schreiber
gewinnt". Würden zwei Eltern gleichzeitig denselben Datensatz beschreiben, ginge ein
Claim verloren, ohne dass jemand es merkt. Zwei Datensätze gehen nicht verloren; die
App entscheidet deterministisch über den frühesten `claimedAt`, bei Gleichstand über
die UUID.

> Abweichung vom Datenmodell-Dokument v1: dort stand `ifServerRecordUnchanged`.
> Das setzt die direkte CloudKit-API voraus und ist mit `NSPersistentCloudKitContainer`
> nicht erreichbar. Die Lösung oben erreicht dasselbe Ziel ohne diese Abhängigkeit.

## 6. Weiches Löschen

Termine werden über `deletedAt` gelöscht, nie hart. Ein hart gelöschter Datensatz kehrt
über ein Gerät zurück, das länger offline war.

## 7. Alle Core-Data-Attribute sind optional

CloudKit verlangt das. Pflichtfelder werden in den Service-Funktionen durchgesetzt,
nicht im Modell. Unique Constraints sind mit CloudKit nicht erlaubt; Eindeutigkeit von
Importen läuft über `externalIdentifier` plus Haushalt.

## 8. Farben nur über Tokens

Kein Hex-Wert in einem View. `Palette.color("person2")` liefert für Hell- und
Dunkelmodus unterschiedliche Werte mit gleicher Bedeutung. "Anna ist grün" muss in
beiden Modi stimmen.

## 9. Die App darf beim Start nicht sterben

`loadPersistentStores` schlägt im Auslieferungsstand nicht mit `fatalError` fehl.
Eine App, die wegen eines defekten Stores nicht startet, ist für die Familie nicht mehr
reparierbar. Fehler werden protokolliert, im Debug-Build zusätzlich als Assertion.

## 10. Jeder KI-Pfad hat einen Pfad ohne KI

Die App muss auf einem Gerät ohne Apple Intelligence vollständig bedienbar bleiben.
Verfügbarkeit wird geprüft und in `CDDeviceRegistration.supportsOnDeviceModel` gehalten,
nicht angenommen.

## 11. Neue Objekte gehören in den Store ihres Haushalts

Bei eingeladenen Mitgliedern liegt der Haushalt im geteilten Store, beim Owner im
privaten. Jedes neue Objekt, das an einem Haushalt oder Termin hängt, wird vor dem
Speichern mit `PersistenceController.assign(_:toStoreOf:)` demselben Store zugeordnet.
Sonst landet es im privaten Store, und das Speichern scheitert an der Store-Grenze
(Regel 3). Die Service-Funktionen in `HouseholdService` und `EventService` tun das
bereits; neue Anlage-Funktionen müssen es auch.

## 12. "Ich" ist gerätelokal

Welches Mitglied ein Gerät benutzt, steht in `UserDefaults` (`CurrentMember`), nicht in
CloudKit. Jedes iPhone hat sein eigenes "ich".

## 13. Modelländerungen: neue Version, erst Schema, dann App

Das Core-Data-Modell wird nie in place geändert, sondern als neue Modellversion
(`Familienplaner N.xcdatamodel`, `.xccurrentversion` umstellen). Nur Ergänzungen
(neue optionale Attribute/Entitäten), nie Umbenennen, Löschen oder Umtypen: CloudKit
Production erlaubt das nicht.

Reihenfolge: (1) Workflow `CloudKit-Schema` (Branch `cloudkit-schema`) legt die neuen
Felder in Development an, (2) David übernimmt sie im CloudKit-Dashboard nach
Production, (3) erst dann ein TestFlight-Build. Sonst lehnt Production die Datensätze
mit den neuen Feldern ab.

## 14. Kalenderübernahme: ein Termin, auch bei gemeinsamen Kalendern

Übernommene Termine tragen als `externalIdentifier` die Serverkennung des Kalenders
(`calendarItemExternalIdentifier`) plus Datum des Vorkommens. Findet ein Gerät einen Termin
mit diesem Schlüssel, den ein anderes Mitglied schon übernommen hat, legt es keinen zweiten
an, sondern hängt sein Mitglied als Betroffenen an (Spiegel-Status `joined`). Entstehen
trotzdem Doppelte (zwei Geräte gleichzeitig), bleibt der Termin mit der kleinsten UUID.
Beim Aktualisieren eigener Übernahmen bleiben angehängte Mitglieder erhalten.

## 15. Die Apple Watch hat keinen eigenen Datenbestand

Die Watch-App bekommt vom iPhone per WatchConnectivity einen fertigen Ausschnitt
(`WatchSnapshot`, Ordner `Shared/`). Titel und Orte sind darin schon für das Mitglied
reduziert (Regel 2, Kinderansicht). Aktionen der Watch ("Übernehme ich") gehen als
Nachricht ans iPhone und werden dort über die Service-Funktionen gespeichert. Kein
CloudKit, kein Core Data auf der Watch.

## 16. Terminserien sind einzelne Termine

Eine Serie ("jeden Dienstag Schwimmen") wird als einzelne `CDEvent`-Datensätze mit
gemeinsamer `seriesParentID` und der Regel in `recurrenceRule` (Teilmenge von RFC 5545)
gespeichert, rollierend für 26 Wochen im Voraus (`SeriesService`). Grund: Zuständigkeiten
gelten pro Termin ("wer holt am 14.10.?"), und Verschieben, Suche, Erinnerungen und Watch
arbeiten ohne Sonderfall. Nachgelegt wird beim Start und im Hintergrund vom Gerät des
Mitglieds, das die Serie angelegt hat. Einzeln gelöschte Termine bleiben weich gelöscht
stehen (Regel 6) und werden deshalb nicht neu angelegt. Doppelte aus gleichzeitigem
Nachlegen: es bleibt die kleinste UUID, Übernahmen wandern mit (wie Regel 14).
Keine Modelländerung nötig: die Felder stehen seit Version 1 im Schema.

## 17. Serienübernahmen und iPhone-Kalender

**Serienübernahme:** Wer eine Zuständigkeit "für die ganze Serie" übernimmt, bekommt je
Termin eine eigene Beteiligung (Regel 5) mit `note = "series"`. Beim Nachlegen (Regel 16)
werden solche Übernahmen des letzten Termins auf die neuen Termine übertragen. Abgeben
"für alle folgenden" setzt die eigenen Beteiligungen auf "abgelehnt"; damit endet die
Übertragung. Keine Modelländerung: `note` steht seit Version 1 im Schema.

**Vorabend-Abfrage:** Offene Zuständigkeiten erscheinen am Vorabend als Mitteilung mit
den Knöpfen "Übernehme ich" und bei Serien "Für die ganze Serie"; gespeichert wird über
`ClaimActions` (gleicher Weg wie die Watch).

**iPhone-Kalender:** Pro Gerät einstellbar (Aus / meine / alle). `CalendarExportService`
schreibt in einen eigenen Kalender "Family Planner", nur in diese Richtung. Erkennung über
die URL `familyplanner://event/<UUID>`; Doppelte (iPhone und iPad derselben Apple-ID im
selben iCloud-Kalender) werden entfernt. Dieser Kalender ist von der Übernahme
ausgenommen (Schleife). Eigene übernommene Termine werden nicht zurückgeschrieben.
Zeitvergleich mit 1 Sekunde Toleranz, sonst schaukeln sich Übernahme und Eintrag auf.

## 18. Ganztägige Termine

`isAllDay = true`, `startAt` = 0 Uhr des ersten Tages, `endAt` = 0 Uhr nach dem letzten
Tag (exklusiv), immer über `EventService.allDaySpan` normalisiert (rundet auf ganze Tage,
damit Zeitumstellung und EventKit-Enden um 23:59:59 passen). Sie erscheinen nicht im
Zeitstrahl, sondern in der Leiste darüber, haben keine Zuständigkeiten und keine
Uhrzeit-Erinnerung. Übernahme und Eintrag in iPhone-Kalender vergleichen nach Tagen.

## Arbeitsweise mit GitHub Actions (Vorgabe David, 26.09.2026)

- Claude wartet nicht blockierend auf Workflows (keine Warteschleifen mit `sleep`).
  Während einer solchen Schleife kann Claude nicht antworten. Nach einem Push kurz
  melden, das Ergebnis später mit einem einzelnen `git fetch` des Log-Branches abholen.
- Der Workflow `Tests` läuft nur nachts zwischen 2 und 3 Uhr und nur bei neuem Stand
  auf `main`. Kein Push auf einen Branch, der Tests auslöst.
