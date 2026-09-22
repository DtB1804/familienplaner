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

### Aufgabe 4: Entscheidung über den App-Namen ✅ erledigt (22.09.2026)
**Ergebnis:** Anzeigename auf dem Homescreen **"Family Planner"**
(`CFBundleDisplayName` in `Resources/Info.plist`). Target, Modul, Core-Data-Modell
und Bundle-ID bleiben technisch `Familienplaner` bzw. `de.barg.familienplaner`.

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

### Aufgabe 7: Geräteinventar ✅ erledigt (22.09.2026)
**Ergebnis laut David:** Alle iPhones der Familie haben alle gewünschten Funktionen
(inkl. Apple Intelligence). Modell und iOS-Version je Gerät wurden nicht einzeln
erfasst. Regel 10 in CLAUDE.md (Pfad ohne KI) gilt trotzdem weiter.

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

## Block D – App ohne Mac auf die iPhones (TestFlight)

Ergänzt am 22.09.2026. Weg: GitHub Actions baut, signiert und lädt die App zu
TestFlight hoch. Dafür braucht der Build drei Dinge von Ihnen. Alles im Browser.

### Aufgabe 13: App-Eintrag in App Store Connect anlegen ✅ erledigt (23.09.2026)
**Wo:** https://appstoreconnect.apple.com → Apps → Plus-Symbol oben links → Neue App
**Eintragen:**
- Plattform: iOS
- Name: `Family Planner`. Ist der Name schon vergeben, eine Variante wählen
  (z. B. `Family Planner Barg`). Der Name auf dem Homescreen bleibt trotzdem
  "Family Planner", der kommt aus der App selbst.
- Primäre Sprache: Deutsch
- Bundle-ID: `de.barg.familienplaner` aus der Liste wählen
- SKU: frei wählbar, z. B. `familienplaner-001`
- Nutzerzugriff: Voller Zugriff
**Hinweis:** Vorher ggf. unter "Business" die aktuelle Vereinbarung bestätigen,
sonst lässt App Store Connect keinen App-Eintrag zu.
**Zuliefern:** Bestätigung und der gewählte Name.

### Aufgabe 14: API-Schlüssel erzeugen ✅ erledigt (23.09.2026)
**Wo:** App Store Connect → Benutzer und Zugriff → Reiter "Integrationen" →
links "App Store Connect API" → "Team-Schlüssel" → Plus / "API-Schlüssel generieren"
**Eintragen:** Name z. B. `github-build`, Zugriff: **Admin**.
Warum Admin: Das Signieren für TestFlight ohne Mac nutzt von Apple verwaltete
Verteilzertifikate. Laut Entwicklerforum klappt das per API-Schlüssel nur mit Admin.
**Danach:** Schlüssel **einmal** herunterladen (Datei `AuthKey_XXXX.p8`, Apple bewahrt
keine Kopie auf). Notieren: **Key-ID** (in der Tabelle) und **Issuer-ID** (über der Tabelle).
**Nicht** in den Chat und nicht ins Repo kopieren – siehe Aufgabe 15.

### Aufgabe 15: Schlüssel als GitHub-Secrets hinterlegen ✅ erledigt (23.09.2026)
**Ergebnis:** Erster Upload zu TestFlight erfolgreich (Build 2, Version 0.1.0,
Workflow `TestFlight`, ausgelöst durch Push auf Branch `testflight`).
Signierung: Archiv ad hoc signiert, echte Signierung beim Export mit von Apple
verwalteten Zertifikaten. Kein registriertes Gerät und kein Mac nötig.

**Wo:** github.com/DtB1804/familienplaner → Settings → links "Secrets and variables"
→ "Actions" → "New repository secret". Drei Secrets anlegen:

| Name | Inhalt |
|---|---|
| `ASC_KEY_ID` | Key-ID aus Aufgabe 14 |
| `ASC_ISSUER_ID` | Issuer-ID aus Aufgabe 14 |
| `ASC_KEY_P8` | kompletter Inhalt der `.p8`-Datei (mit Editor öffnen, alles kopieren inkl. `-----BEGIN PRIVATE KEY-----` und `-----END PRIVATE KEY-----`) |

Secrets sind auch im öffentlichen Repo nicht lesbar, auch nicht für Claude. Nur der
Build darf sie benutzen.
**Zuliefern:** "Secrets angelegt".

### Aufgabe 16: Tester eintragen (erst wenn der erste Build in TestFlight liegt)
- David: automatisch als Account Holder.
- Jana: in App Store Connect unter "Benutzer und Zugriff" als Benutzer einladen
  (Rolle z. B. "Developer" oder "Marketing"), danach als interne Testerin eintragen.
  Interne Tests brauchen keine Beta-Prüfung durch Apple.
- Josh: offen. Interne Tester müssen App-Store-Connect-Benutzer sein; ob das mit
  einem Kinderaccount geht, ist ungeklärt. Alternative: externe Tester per Einladung,
  dafür prüft Apple den Build einmal vorab (Beta App Review).
- Auf jedem iPhone die App "TestFlight" aus dem App Store installieren.

### Offener Punkt: CloudKit-Schema
TestFlight-Builds nutzen immer die **Production**-Umgebung von CloudKit. Dort muss das
Schema vorher bereitgestellt sein, und dafür muss es erst in Development existieren
(Aufgaben 10 und 12). Ohne Mac klärt Claude den Weg dorthin (Kandidat: Schema per
`cktool` auf dem GitHub-Mac hochladen, dann im CloudKit-Dashboard nach Production
übernehmen). Bis das gelöst ist, startet die App aus TestFlight, aber der Abgleich
über iCloud funktioniert noch nicht.

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
