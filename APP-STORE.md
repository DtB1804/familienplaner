# Veröffentlichung „nicht gelistet“ – Texte und Ablauf

Entscheidung David, 28.09.2026: Verteilung als **nicht gelistete App** (App Store, nur per
Direktlink auffindbar). Quelle Ablauf: https://developer.apple.com/support/unlisted-app-distribution
Apple beschreibt als typische Fälle Firmen-, Partner- und Studien-Apps; ob eine Familien-App
angenommen wird, ist offen. Fallback bei Ablehnung: TestFlight weiter nutzen.

## Ablauf (laut Apple)

1. App regulär in App Store Connect vorbereiten und **zur Prüfung einreichen**, in den
   Prüfhinweisen (Review Notes) vermerken, dass nicht gelistete Verteilung gewünscht ist.
2. Danach den **Antrag** stellen: https://developer.apple.com/contact/request/unlisted-app/
   Anträge für Apps, die noch nicht eingereicht sind oder im Beta-Stadium, lehnt Apple ab.
3. Nach Freigabe gibt es einen Direktlink; nur wer ihn hat, findet die App.

## Pflichtangaben (Vorschläge zum Einfügen)

**Name:** Family Planner  (Hinweis: Der Name muss im App Store noch frei sein; zeigt
App Store Connect beim Anlegen.)
**Untertitel (max. 30 Zeichen):** Wer bringt, wer holt, wann
**Kategorie:** Lifestyle (primär), Produktivität (sekundär)
**Copyright:** 2026 [VORNAME NACHNAME]
**Support-URL:** https://dtb1804.github.io/familienplaner/  (nach Aktivierung von GitHub Pages)
**Datenschutz-URL:** https://dtb1804.github.io/familienplaner/datenschutz.html
**Preis:** kostenlos

**Beschreibung:**

Family Planner zeigt den Tag der ganzen Familie nebeneinander: eine Spalte pro Person,
damit auf einen Blick klar ist, wer wann gebunden ist und wo es sich überschneidet.

- Wer bringt, wer holt, wer begleitet: offene Aufgaben stehen oben, übernehmen geht mit
  einem Tipp, auch am Vorabend direkt aus der Mitteilung.
- Tag, Woche und Monat; Termine per Ziehen verschieben, mit Rückgängig.
- Terminserien wie „jeden Dienstag Schwimmen“, ganztägige Termine wie Ferien und Urlaub.
- Eigene Kalender einbinden, z. B. den Dienstplan nur als „Belegt“: Titel und Ort
  verlassen das iPhone nicht.
- Termine aus Elternbriefen: fotografieren, Screenshot oder Text teilen, Vorschläge prüfen
  und eintragen. Die Erkennung läuft auf dem Gerät.
- Freie Zeit finden: wann haben alle gleichzeitig frei?
- Widgets, Apple Watch und Zifferblatt-Komplikationen.
- Kein eigener Server, kein Konto, keine Werbung: Die Daten liegen in eurer iCloud.

**Schlüsselwörter (max. 100 Zeichen):**
Familie,Kalender,Termine,Kinder,bringen,holen,Elternbrief,Familienkalender,Planer,Schule

**Barrierefreiheit (Angabe):** VoiceOver, Dynamische Schrift; per nächtlichem Test mit
Apples Barrierefreiheitsprüfung kontrolliert. Nur ankreuzen, was auf dem Gerät geprüft ist.

## Hinweise für die Prüfer (Review Notes)

> Family Planner is a private family calendar. We request unlisted distribution: the app is
> intended only for members of our family who receive the direct link.
>
> No login is required. Data is stored in the user's iCloud (CloudKit private database) and
> shared with invited family members via CloudKit sharing (CKShare). There is no server
> operated by the developer.
>
> To try it: open the app, create a household ("Einrichten"), add a member under "Familie",
> create an appointment with "+". Photo/text import: "Foto oder Text" → paste text such as
> "Elternabend am 21.10. von 19:00 bis 20:30". Sharing requires a second Apple ID and is
> optional for review.
>
> Permissions are optional: calendars (show selected calendars to the family, optionally as
> "busy" only), camera/photos (on-device text recognition), notifications (reminders).

## App-Datenschutzangaben (App Store Connect → App-Datenschutz)

Nicht vorab festgelegt; gemeinsam anhand von Apples Fragebogen ausfüllen. Fakten für die
Beantwortung: kein eigener Server, keine Analyse- oder Werbedienste, keine Weitergabe an
Dritte durch den Entwickler; Speicherung in iCloud des Nutzers (Apple).

## Antrag „nicht gelistet“ – Textvorschlag

> App name: Family Planner. Apple ID of app: [aus App Store Connect].
> Audience: members of a single family (parents and children) who use the app to coordinate
> appointments and pick-ups. The app will be shared via direct link only. It is not intended
> for the general public.

## DSA-Händlerstatus

Angabe in App Store Connect nötig. Als „Händler“ zeigt Apple Anschrift, Telefon und E-Mail
öffentlich. Als „Nicht-Händler“ erhalten EU-Nutzer den Hinweis, dass Verbraucherrechte
nicht gelten. Entscheidung David (rechtliche Frage, ggf. prüfen lassen).
Quelle: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
