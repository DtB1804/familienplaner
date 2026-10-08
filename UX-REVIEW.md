# UX-Prüfung Family Planner (Stand Build 28, 28.09.2026)

Grundlage: Durchsicht des Oberflächen-Codes (TodayScreen, DayTimelineView, EventEditorSheet,
MembersScreen, Onboarding, Setup, FreeTime, Vorschläge, Kalender, Erinnerungen, Watch).
Kein Test mit echten Nutzern und kein Gerät. Aussagen zur Wirkung auf Nutzer sind
Einschätzungen, keine Messungen.

**Umsetzung:** A1–A6 und D in Build 29. B1–B10 in Build 30/31. C in Build 32 (Hinweis im iPhone-Kalender war schon vorhanden; ein direkter Sprung in die iCloud-Einstellungen ist mit öffentlicher Apple-Schnittstelle nicht möglich, daher „Erneut prüfen“).

## A. Vor dem Livegang beheben

**A1 · Verschieben ohne Rückgängig.** Halten und Ziehen verschiebt sofort und synchronisiert
an alle Geräte (`TodayScreen.move`, `reassignSubject`). Beim Scrollen mit kurzem Halten
passiert das leicht aus Versehen. Diagonales Ziehen ändert gleichzeitig Zeit und Person.
Bei Serienterminen fragt das Ziehen nicht „nur dieser?“, der Editor schon.
*Vorschlag:* Hinweis unten „Schwimmen → 17:15 · Rückgängig“ (5 s), Ziehen entweder vertikal
oder seitlich (Achse nach den ersten Punkten festlegen).

**A2 · „Übernehme ich“ fehlt am Termin.** Erwachsene öffnen per Tippen den Editor. Dort
gibt es „Abgeben“, aber kein „Übernehmen“. Übernehmen geht nur über das Banner
„offene Zuständigkeiten“ oder die Mitteilung. Wer das „Holt ?“ am Termin sieht und
draufdrückt, findet den Knopf nicht.
*Vorschlag:* Im Editor und in der Detailansicht je offener Rolle „Übernehme ich“.

**A3 · Foto und Kamera sind versteckt.** „+“ ist ein Menü mit `primaryAction`: Tippen legt
einen Termin an, erst langes Drücken zeigt „Termine fotografieren“, „Termine aus Foto“ und
„Offene Vorschläge“. Das findet kaum jemand.
*Vorschlag:* Tippen öffnet das Menü mit den drei Wegen, oder eigener Kamera-Knopf.
Offene Vorschläge als Banner wie die Zuständigkeiten.

**A4 · Kein Weg zurück zu „Heute“.** Nur Pfeile und Wischen. Nach dem Blättern in den
November heißt es viele Male tippen. Ein Datum direkt wählen geht nicht.
*Vorschlag:* Titel antippbar → Datumsauswahl; „Heute“-Knopf, sobald nicht heute.

**A5 · Einladung weckt falsche Erwartung.** Beim Anlegen steht bei „Eigenes iPhone“:
„bekommt anschließend eine Einladung“. Es passiert aber nichts; man muss selbst auf
„Familie einladen“. Umgekehrt: Hat der Owner den Schalter vergessen, sieht die eingeladene
Person dauerhaft „Familie wird geladen“ (`IdentityPickerScreen`, leere Kandidatenliste),
obwohl längst alles geladen ist. Sackgasse genau beim ersten Eindruck.
*Vorschlag:* Nach „Sichern“ mit eigenem iPhone direkt das Einladungsblatt öffnen. Im
Auswahlbildschirm nach dem Laden „Dein Name fehlt?“ statt Ladehinweis.

**A6 · Haushalt löschen mit einem Tipp bestätigt.** Löscht für die ganze Familie
unwiderruflich, Bestätigung ist ein einzelner Dialogknopf; Export wird nur im Fußtext empfohlen.
*Vorschlag:* Im Dialog zuerst „Vorher sichern (.ics)“ anbieten, dann Haushaltsnamen eintippen.

## B. Wichtig

**B1 · Sie und Du gemischt.** Einrichten, Familie, Kalender, Erinnerungen, Vorschläge
sagen „Sie“, Erste Schritte sagt „Du“. Für eine Familien-App durchgehend „Du“.

**B2 · Begriffe.** „Übernehmen“ bedeutet dreierlei: Zuständigkeit übernehmen, Kalender
übernehmen, Foto-Vorschlag übernehmen. „Haushalt-Owner“ ist Englisch. „Zuständigkeiten“
klingt nach Amt. Im Editor steht „Bringt nötig“, „Holt nötig“, „Begleitet nötig“
(grammatisch schief).
*Vorschlag:* „Wer bringt? / Wer holt? / Wer begleitet?“; Kalender „anzeigen“ statt
„übernehmen“; Vorschlag „Eintragen“; „Verwalter:in“ oder „wer den Haushalt angelegt hat“.

**B3 · Editor zu lang, Wichtiges unten.** Reihenfolge: Art, Titel, Zeit, Wiederholen,
Für wen, Belegt-Schalter, Zuständigkeiten, Details, Notizen. Bringen/Holen, der Kern der
App, liegt unter der Falz; die nächtlichen UI-Tests mussten dafür extra scrollen.
*Vorschlag:* Titel, Zeit, Für wen, Wer bringt/holt oben; Wiederholen, Belegt, Kategorie,
Ort, Notizen darunter oder eingeklappt.

**B4 · Tippen öffnet sofort den Editor.** Erwachsene sehen ihre eigenen Termine nie in
der ruhigen Detailansicht; jedes Nachschauen ist ein Bearbeiten-Formular, „Abbrechen“
verwirft. Kalender-App-Muster: Details zuerst, „Bearbeiten“ oben rechts.

**B5 · Viel Kopf, wenig Kalender.** Über dem Zeitstrahl können bis zu sechs Leisten
stehen: iCloud-Hinweis, Kindervorschau, Personenchips, offene Zuständigkeiten,
Tag/Woche mit Lupen, Ganztags-Leiste. Auf einem kleineren iPhone bleibt die halbe Höhe.
*Vorschlag:* Lupen weg (Zwei-Finger-Zoom und Menü reichen), Tag/Woche in die Titelzeile,
Zuständigkeiten als Zähler-Chip in der Personenleiste.

**B6 · Personenfilter doppeldeutig.** Ohne Auswahl sind alle zu sehen, die Chips wirken
aber alle „aus“. Nach Antippen einer Person verschwinden die anderen Spalten; zurück nur
über „Alle“, der erst dann erscheint.
*Vorschlag:* Im Grundzustand alle Chips als „an“ zeigen; Antippen blendet eine Person aus.

**B7 · Kurze Termine schwer zu treffen.** In Standardzoom (52 pt/Stunde) ist ein
15-Minuten-Termin 13 pt hoch, 30 Minuten 26 pt. Apple empfiehlt mindestens 44 × 44 pt
für Bedienelemente. *Vorschlag:* Trefferfläche größer als die sichtbare Fläche
(`contentShape` mit Mindesthöhe).

**B8 · Zeitstrahl nur 6–23 Uhr.** Termine davor oder danach (Frühflug, Feier bis 23:30)
werden abgeschnitten oder liegen außerhalb des Scrollbereichs.
*Vorschlag:* Bereich an die Termine des Tages anpassen, sonst 6–23.

**B9 · Halten bedeutet zweierlei.** Bei eigenen Terminen startet Halten das Ziehen, bei
übernommenen Kalenderterminen öffnet es die Details. Kein sichtbarer Unterschied.

**B10 · Kinder sehen das Zuständigkeiten-Banner**, können dort aber nichts tun. Für Kinder
ausblenden oder als Info („Papa holt dich“) umformulieren.

## C. Kleinigkeiten

- „Sichern“ ist ausgegraut, ohne zu sagen, was fehlt (Titel? Person?).
- iCloud-Hinweis öffnet nur einen Text mit „OK“; ein Knopf „Einstellungen öffnen“ fehlt.
- Einträge im iPhone-Kalender „Family Planner“ lassen sich dort ändern und werden dann still
  überschrieben. Im Termin-Notizfeld dort einen Satz „Bitte in Family Planner ändern“.
- Erinnerungen: Fußtext sagt, Änderungen anderer zählen erst nach dem nächsten Öffnen. Das
  untergräbt Vertrauen; prüfen, ob die Hintergrundaktualisierung das schon abdeckt, und Text anpassen.
- „Frei“ in der Werkzeugleiste ist unklar; „Freie Zeit“.
- „Mitglied entfernen“: Was mit künftigen Terminen der Person passiert, steht nicht da.

## D. Außerhalb UX, aber dringend

Im öffentlichen Repo stehen Familiennamen: `ReminderSettingsScreen.swift` Zeile 36
(„Holt Josh“) und `README.md` Zeilen 105–106 (Jana, Josh). Das widerspricht der Regel
„keine Familiennamen im öffentlichen Repo“. Ersetzen durch Mia/Tom; die Namen bleiben in
der Git-Historie, solange sie nicht umgeschrieben wird.

## E. Empfohlener Nutzertest (mit Jana, 20 Minuten)

Ohne Erklärung, laut denken lassen, nur zuschauen:
1. „Trag Schwimmen jeden Dienstag 16 Uhr für Mia ein, Holen ist offen.“
2. „Übernimm das Holen am nächsten Dienstag.“ (prüft A2)
3. „Fotografier diesen Elternbrief und trag die Termine ein.“ (prüft A3)
4. „Schau, was am 14. November los ist, und dann wieder heute.“ (prüft A4)
5. „Wann haben alle vier nächste Woche zwei Stunden frei?“

Quelle Trefferfläche: Apple, UI Design Dos and Don’ts, https://developer.apple.com/design/tips/
