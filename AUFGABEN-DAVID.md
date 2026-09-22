# Aufgaben, die nur David erledigen kann

Alles hier braucht entweder Ihre Apple-ID, Ihre Kreditkarte, Ihre echten Geräte oder
eine Entscheidung, die Ihnen gehört. Nichts davon lässt sich aus einer Cloud-Umgebung
heraus tun.

Die Reihenfolge ist die Reihenfolge. Aufgaben 1 bis 4 blockieren den ersten Build,
Aufgabe 6 kann noch das Datenmodell verändern.

---

## Block A – bevor der erste Build laufen kann

### Aufgabe 1: Mac mit Xcode einrichten – ❌ entfällt, kein Mac verfügbar (22.09.2026)
**Ersatz:** Build über GitHub Actions mit macOS-26-Runner (Xcode 26.x vorinstalliert).
Siehe Aufgabe 1a.

~~**Was:** Xcode aus dem Mac App Store installieren, einmal starten, Lizenz bestätigen,
iOS-Simulator-Runtime laden lassen.
**Warum nur Sie:** Braucht Ihren Mac.
**Zuliefern:** Xcode-Version (Menü Xcode → About Xcode).
**Aufwand:** 30 bis 60 Minuten, davon fast alles Download.~~

### Aufgabe 1a: GitHub-Repository für Cloud-Builds ✅ erledigt (22.09.2026)
**Ergebnis:** öffentliches Repo https://github.com/DtB1804/familienplaner, Workflow
`Build` baut bei jedem Push auf `main`; Log liegt im Branch `ci-log`.

**Was:** GitHub-Account (falls nicht vorhanden), Repository anlegen, Claude einen
Zugang zum Pushen geben (Personal Access Token mit Rechten nur auf dieses Repo).
**Entscheidung:** privat (macOS-Minuten kosten laut GitHub 0,062 USD/Minute; ob und wie
die Freiminuten greifen, ist ungeklärt) oder öffentlich (Standard-Runner kostenlos).
**Zuliefern:** Repo-URL und Token, oder die Entscheidung.

### Aufgabe 2: Apple Developer Program einschreiben ✅ erledigt
**Ergebnis:** Team-ID `KF96Z9PD9Q`, in `project.yml` eingetragen.

**Was:** Mitgliedschaft für 99 USD im Jahr abschließen.
**Warum nicht der kostenlose Account:** Er erlaubt nur drei Testgeräte je Plattform,
die Provisionierung läuft nach sieben Tagen ab und er bietet keinerlei Verteilung,
auch kein TestFlight. Bei vier oder mehr Familiengeräten im Dauerbetrieb ist das
nicht praktikabel.
**Zuliefern:** Ihre **Team-ID** (10 Zeichen, im Developer-Portal unter Membership).
Ohne sie schlägt jede Signierung fehl.
**Aufwand:** 20 Minuten plus bis zu 48 Stunden Freischaltung durch Apple.

### Aufgabe 3: Bundle-ID und iCloud-Container festlegen ✅ erledigt (22.09.2026)
**Was:** Im Developer-Portal unter Identifiers anlegen:
- App-ID: `de.barg.familienplaner` (oder ein anderer Wert, dann überall anpassen)
- iCloud-Container: `iCloud.de.barg.familienplaner`

Beim App-ID-Eintrag die Capabilities **iCloud (mit CloudKit)** und
**Push Notifications** aktivieren und den Container zuordnen.
**Warum nur Sie:** Braucht Ihren Developer-Account.
**Zuliefern:** Bestätigung, dass beide Einträge existieren, oder die abweichenden Namen.
**Aufwand:** 15 Minuten.

### Aufgabe 4: Entscheidung über den App-Namen
**Was:** `Familienplaner` ist ein Arbeitstitel. Der Name steht auf dem Homescreen jedes
Familienmitglieds.
**Warum nur Sie:** Geschmacksfrage, und Ihre Familie sieht ihn täglich.
**Zuliefern:** Name, oder die Ansage, dass der Arbeitstitel bleibt.
**Aufwand:** 5 Minuten.

---

## Block B – Daten, die ich für den Code brauche

### Aufgabe 5: Familienmitglieder benennen ✅ erledigt (22.09.2026)
**Ergebnis:** 2 Erwachsene, 2 Kinder; ein Kind ohne eigene Apple-ID (→ verwaltetes
Profil, `MemberAccountKind.managed`). Namen und Details bewusst **nicht** in diesem
öffentlichen Repo, sondern nur im privaten Claude-Projekt (`FAMILIE-PRIVAT.md`).
Die App erfasst die Personen beim Erststart, nicht im Code.

**Was:** Für jede Person: Anzeigename, zwei- bis dreistelliges Kürzel für den
Spaltenkopf, Rolle (Erwachsener oder Kind), und ob die Person ein eigenes iPhone mit
eigener Apple-ID hat.
**Format, das ich direkt verwenden kann:**

| Anzeigename | Kürzel | Rolle | Eigene Apple-ID | Alter |
|---|---|---|---|---|
| David | Da | Erwachsener | ja | – |
| … | … | … | … | … |

**Warum nur Sie:** Sind Ihre Daten.
**Zuliefern:** Die ausgefüllte Tabelle.
**Aufwand:** 10 Minuten.

### Aufgabe 6: CKShare-Test mit einem Kinderaccount ✅ erledigt (22.09.2026)
**Ergebnis:** Freigabe über Notizen hat mit dem Kinderaccount funktioniert.
Kinder mit eigener Apple-ID werden echte CloudKit-Teilnehmer (`participant`).

**Was:** Praktisch prüfen, ob ein Apple-Account eines Kindes unter 13 aus Ihrer
Familienfreigabe eine CloudKit-Freigabe annehmen kann.

So geht es ohne die App: In der Notizen-App eine Notiz anlegen, über das
Teilen-Symbol mit dem Apple-Account des Kindes teilen, auf dem Kind-iPhone
annehmen lassen. Notizen nutzt denselben Freigabemechanismus.

**Warum nur Sie:** Braucht zwei echte Geräte und zwei echte Accounts.
**Warum kritisch:** Ich habe zu dieser Frage trotz Suche keine belastbare Aussage in
Apples Dokumentation gefunden. Schlägt der Test fehl, laufen die Kinderkalender als
verwaltete Profile über Ihr Gerät. Das Datenmodell trägt beides, aber die UI wird
anders. Deshalb vor dem UI-Ausbau klären.
**Zuliefern:** Hat funktioniert / hat nicht funktioniert, bei Fehlschlag die genaue
Meldung.
**Aufwand:** 15 Minuten.

### Aufgabe 7: Geräteinventar
**Was:** Für jedes iPhone in der Familie: Modell, iOS-Version, und ob unter
Einstellungen → Apple Intelligence & Siri die Funktion verfügbar und aktiviert ist.
**Warum nur Sie:** Braucht die Geräte in der Hand.
**Zuliefern:** Liste.
**Aufwand:** 10 Minuten.

### Aufgabe 8: Familienentscheidung "wer sieht was" ✅ entschieden (22.09.2026)
**Ergebnis:**
1. Dienstkalender: für die Familie **"Belegt" oder gar nicht** (wählbar). Wo keine
   Kalenderverbindung oder kein Export möglich ist, werden Dienste **manuell**
   eingetragen.
2. Kinder sehen Termine der Erwachsenen **mit Titel oder nur als "Belegt"**, per
   Schalter umstellbar (Anzeige-Einstellung, siehe Hinweis unten).
3. Kinder sehen die Termine des jeweils anderen Kindes: **ja**.

**Hinweis zu 2:** CloudKit kennt keine Rechte auf Feldebene (CLAUDE.md, Regel 2).
Liegen Erwachsenentermine mit Titel in der Zone, die ein Kinderaccount liest, ist
"nur Belegt" eine Anzeige-Einstellung, kein Schutz.
**Entschieden (22.09.2026):** Anzeige-Schalter reicht, keine eigene Kinder-Zone.

**Was:** Drei Festlegungen, die ich als Vorgabewerte in den Code schreibe:
1. Soll Ihr Dienstkalender für die Familie sichtbar sein als "Belegt" oder gar nicht?
2. Sollen die Kinder die Termine der Erwachsenen sehen, und wenn ja, mit Titel oder nur
   als Belegtzeit?
3. Sollen die Kinder die Termine des jeweils anderen Kindes sehen?

**Warum nur Sie:** Familienentscheidung, keine technische.
**Zuliefern:** Drei Antworten.
**Aufwand:** ein Gespräch am Abendbrottisch.

---

## Block C – nach dem ersten Build

### Aufgabe 9: Erster Build und Rückmeldung der Fehler – ✅ übernimmt Claude per CI
**Ergebnis 22.09.2026:** Simulator-Build mit Xcode 26.6 / iOS-Simulator-SDK 26.5
erfolgreich (`BUILD SUCCEEDED`, alle 11 Swift-Dateien plus Core-Data-Modell kompiliert).
Nicht getestet: Start der App, Verhalten zur Laufzeit.

**Was:** `xcodegen generate`, Projekt öffnen, Build starten.
**Realistische Erwartung:** Der Code ist ohne Swift-Compiler geschrieben. Rechnen Sie
mit einer Handvoll Fehler, meist Tippfehler oder API-Signaturen, die sich in iOS 26
geändert haben.
**Zuliefern:** Die Fehlermeldungen als Text oder Screenshot. Ich korrigiere sie
gezielt. Bitte nicht selbst raten, das kostet mehr Zeit als es spart.
**Aufwand:** 30 Minuten plus Korrekturschleifen.

### Aufgabe 10: CloudKit-Schema erzeugen
**Was:** In `PersistenceController.swift` die Zeile
`try? container.initializeCloudKitSchema(options: [])` einmalig einkommentieren, App im
Simulator mit angemeldeter Apple-ID starten, danach die Zeile wieder auskommentieren.
Ergebnis im CloudKit-Dashboard prüfen: alle sechs Cloud-Entitäten müssen als Record
Types erscheinen.
**Warum nur Sie:** Braucht eine angemeldete Apple-ID und Ihren Container.
**Zuliefern:** Screenshot der Record Types oder die Fehlermeldung.
**Aufwand:** 20 Minuten.

### Aufgabe 11: Sync-Test über zwei echte Accounts
**Was:** App auf zwei Geräten mit zwei verschiedenen Apple-IDs installieren, teilen,
auf Gerät A einen Termin anlegen, auf Gerät B warten. Dann ein Gerät in den Flugmodus,
auf beiden etwas ändern, Flugmodus aus.
**Warum nur Sie:** Zwei echte iCloud-Accounts lassen sich nicht simulieren.
**Zuliefern:** Was ankam, was nicht, und wie lange es gedauert hat.
**Aufwand:** über zwei Tage verteilt, jeweils wenige Minuten.

### Aufgabe 12: Schema nach Production deployen
**Was:** Im CloudKit-Dashboard "Deploy Schema Changes" von Development nach Production.
**Wann:** Erst wenn das Modell stabil ist. In Production lassen sich Felder hinzufügen,
aber nicht mehr entfernen oder umtypen.
**Zuliefern:** Bestätigung.
**Aufwand:** 5 Minuten, aber eine Einbahnstraße.

---

## Was ich in der Zwischenzeit weiterbaue

Ohne auf eine dieser Aufgaben zu warten:

- Teilen-Flow über `UICloudSharingController` samt Annahme-Handling
- Kalenderimport über EventKit mit Dedup und Projektion auf "Belegt"
- Termin anlegen und bearbeiten
- Detailansicht der Zuständigkeiten mit dem Übernehmen-Fluss
- Freiraum-Finder

Blockiert sind nur: erster lauffähiger Build (Aufgaben 1 bis 3), die konkrete
Kinder-UI (Aufgabe 6) und alles rund um Verteilung (Aufgabe 2).

---

## Kürzestfassung

Aufgaben 2 und 3 sind erledigt. Kein Mac verfügbar: Builds laufen künftig über
GitHub Actions (Aufgabe 1a). Offen und ohne Mac zu klären: Aufgabe 1a, 6 und Block B.
Aufgabe 10 (CloudKit-Schema) muss für den Weg ohne Mac neu geplant werden, weil
`initializeCloudKitSchema` eine angemeldete Apple-ID im Development-Environment braucht.
