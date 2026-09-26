# Tests – Familienplaner

Automatisiert im Workflow `Tests` (GitHub Actions, macOS 26, Xcode 26.6, Simulator iPhone 17 Pro).
Zeitplan: einmal täglich zwischen 2 und 3 Uhr Hamburger Zeit, nur wenn seit dem letzten
Testlauf ein neuer Stand auf `main` gebaut wurde. Von Hand: GitHub → Actions → Tests → Run workflow.
Ergebnis, Abdeckung und Bildschirmaufnahmen: Branch `ci-log-tests` und Artefakt `test-report`.

## Teststufen

| Stufe | Ort | Umfang |
|---|---|---|
| Werkzeug-Tests (Python) | `tools/tests/` | Schema-Generator: Typabbildung, nur Cloud-Entitäten, **jedes Modellfeld steht im CloudKit-Schema** (Regel 13) |
| Unit- und Integrationstests | `Tests/FamilienplanerTests/` | Terminserien (Regeln, Zeitumstellung, 31./29.2., Nachlegen, Löschen, Doppelte, Serienübernahme, Abgeben), Übernehmen aus Mitteilung/Watch, ganztägige Termine (ganze Tage auch über die Zeitumstellung, mehrtägig, Serie), Inhalt und Auswahl für den iPhone-Kalender, Core Data im Arbeitsspeicher mit allen drei Stores: Projektion (Regel 2), Zuständigkeiten und Claim-Konflikte (Regel 5), weiches Löschen (Regel 6), Store-Zuordnung beim geteilten Haushalt (Regel 11), Kinderansicht, Suche, Zeitraumabfragen, Foto-Vorschlagsregeln, Spracherkennung, Zoom, Wochenbeginn, Watch-Ausschnitt, Erinnerungs-Voreinstellungen, Kalenderschlüssel (Regel 14) |
| Lasttest | `PerformanceTests` | 1.500 Termine (ein Jahr): Woche laden, offene Zuständigkeiten, Suche |
| Smoke-Test | `Tests/FamilienplanerUITests/SmokeTests` | Start, Einrichten gesperrt ohne Eingaben, Haushalt anlegen, Hauptbildschirm vollständig |
| End-to-End | `Tests/FamilienplanerUITests/EndToEndTests` | 1. Termin mit „Holt nötig“ → Hinweis → übernehmen → Suche → Woche → löschen · 2. Drag & Drop verschiebt um ca. 2 h, 15-Minuten-Raster · 3. Wischen blättert Tage · 4. Kindervorschau zeigt „Belegt“, eigene Kindertermine lesbar, keine Bearbeitung · 5. Wöchentliche Serie anlegen, in der Folgewoche sichtbar, „diesen und alle folgenden“ löschen · 6. Serie mit „Holt nötig“ für die ganze Serie übernehmen · 7. Ganztägiger Termin erscheint in der Leiste, nicht im Zeitstrahl |

Die App erkennt Testläufe (`-uiTesting` bzw. Unit-Test-Host, siehe `Sources/App/TestMode.swift`):
Daten nur im Arbeitsspeicher, kein iCloud, gerätelokale Einstellungen zurückgesetzt,
neue Termine um 10:00.

## Nicht automatisierbar (manuell auf Geräten)

- Teilen zwischen zwei Apple-IDs (CKShare-Einladung, Annahme, Abgleich) – braucht echte iCloud-Konten
- Kinder-Account mit eigener Apple-ID, Familienfreigabe
- Kalenderzugriff und Mitteilungen (Systemdialoge), echte iPhone-Kalender, Eintrag in den Kalender „Family Planner“, Knöpfe in Mitteilungen
- Hintergrundabgleich (iOS entscheidet über den Zeitpunkt)
- Apple Watch auf Hardware (Kopplung, WatchConnectivity)
- Termine aus Fotos mit Apple Intelligence (nur auf unterstützten Geräten)

## Letzter Lauf

25.09.2026, Commit `c33ef2e`: 6 Python-Tests, 37 Unit-Tests, 1 Smoke-Test, 4 End-to-End-Tests, alle bestanden.
Zeilenabdeckung App 63,6 %.

Befunde dieses Laufs:
1. **Fehler behoben:** Schalter „Kinder sehen Titel der Erwachsenen-Termine“ zeigte nach dem Antippen
   den alten Stand, weil `MembersScreen` den Haushalt nicht beobachtete (`@ObservedObject` ergänzt).
2. **Bekannte Grenze:** Die Datumserkennung ohne KI (`NSDataDetector`) wertet Tageszeit-Wörter wie
   „evening“ als Teil der Uhrzeit; aus „Parent evening …“ wird der Titel „Parent“. Vorschläge werden
   vor der Übernahme geprüft (Regel 4). Test `testDateDetectorSwallowsDaytimeWords` hält das fest.
