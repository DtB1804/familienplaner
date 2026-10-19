import SwiftUI
import UIKit
import EventKit
import CoreData

/// "Meine Kalender": pro iPhone-Kalender festlegen, was die Familie sieht.
/// Gilt nur für dieses Gerät und dieses Mitglied.
struct CalendarSourcesScreen: View {

    let household: CDHousehold
    let member: CDMember

    @Environment(\.managedObjectContext) private var context

    @State private var hasAccess = CalendarImportService.shared.hasFullAccess
    @State private var denied = CalendarImportService.shared.accessWasDenied
    @State private var calendars: [EKCalendar] = []
    @State private var selection: [String: CalendarVisibility] = [:]
    @State private var otherImporters: [String: [String]] = [:]
    @State private var exportScope = CalendarExportService.scope
    /// Zielkalender für "Eintragen"; leer = Standardkalender für neue Termine.
    @State private var exportTarget = UserDefaults.standard.string(forKey: CalendarExportService.targetIDKey) ?? ""
    @State private var writable: [EKCalendar] = []

    private var service: CalendarImportService { .shared }

    var body: some View {
        List {
            if !hasAccess {
                Section {
                    Text("Danach wählst du für jeden Kalender, ob die Familie Termine mit Titel, nur als „Belegt“ oder gar nicht sieht. Neue Kalender stehen immer auf „Nicht zeigen“.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if denied {
                        Text("Der Zugriff wurde abgelehnt. Du kannst ihn in den iPhone-Einstellungen unter Apps → Family Planner → Kalender ändern.")
                            .font(.footnote)
                        Button("Einstellungen öffnen") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else {
                        // Neutral beschriftet: App Review 15.10.2026 (Guideline 5.1.1(iv)) verlangt
                        // "Weiter" statt eines Knopfs, der zum Erlauben auffordert. Die Entscheidung
                        // fällt allein in Apples Systemabfrage danach.
                        Button("Weiter") {
                            Task { await requestAccess() }
                        }
                        .accessibilityIdentifier("calendars.continue")
                    }
                }
            } else {
                Section {
                    Picker("Eintragen", selection: $exportScope) {
                        ForEach(CalendarExportService.Scope.allCases) { Text($0.label).tag($0) }
                    }
                    .accessibilityIdentifier("export.scope")
                    if exportScope != .off {
                        Picker("In Kalender", selection: $exportTarget) {
                            Text("Standard (\(CalendarExportService.shared.defaultCalendarTitle))").tag("")
                            ForEach(writable, id: \.calendarIdentifier) { calendar in
                                Text("\(calendar.title) · \(calendar.source?.title ?? "")").tag(calendar.calendarIdentifier)
                            }
                        }
                        .accessibilityIdentifier("export.target")
                    }
                } header: {
                    Text("In meinen iPhone-Kalender eintragen")
                } footer: {
                    Text(exportScope == .off
                         ? "Family Planner kann Familientermine direkt in deinen eigenen Kalender eintragen und aktuell halten, ohne zusätzlichen Kalender."
                         : "\(exportScope == .mine ? "Termine, die dich betreffen oder die du übernommen hast" : "Alle Termine der Familie"), eine Woche zurück bis sechs Monate voraus. Termine aus deinen eigenen Kalendern stehen dort schon und werden nicht doppelt eingetragen. Änderungen erscheinen automatisch. Bearbeite diese Termine in Family Planner, im Kalender werden Änderungen überschrieben. Deine übrigen Termine fasst Family Planner nicht an.")
                }
                ForEach(groupedSources, id: \.0) { sourceTitle, items in
                    Section(sourceTitle) {
                        ForEach(items, id: \.calendarIdentifier) { calendar in
                            row(for: calendar)
                        }
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("Aus deinen Kalendern: Bei „Nur als „Belegt““ bleiben Titel, Ort und Notizen auf diesem iPhone. Gezeigt wird eine Woche zurück bis drei Monate voraus.")
                }
            }
        }
        .navigationTitle("Meine Kalender")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: exportTarget) { _, target in
            CalendarExportService.shared.setTarget(target.isEmpty ? nil : target)
        }
        .onChange(of: exportScope) { _, scope in
            CalendarExportService.scope = scope
            if scope == .off {
                CalendarExportService.shared.removeAll()
            } else {
                CalendarExportService.shared.sync()
            }
            reload()
        }
    }

    private func row(for calendar: EKCalendar) -> some View {
        HStack(spacing: Spacing.m) {
            // Farbe des Kalenders aus dem System, kein eigener Farbwert der App.
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.title)
                if let names = otherImporters[calendar.calendarIdentifier], !names.isEmpty {
                    Text("Auch von \(names.joined(separator: ", ")) übernommen – gleiche Termine werden zusammengeführt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("", selection: Binding(
                get: { selection[calendar.calendarIdentifier] ?? .hidden },
                set: { newValue in
                    selection[calendar.calendarIdentifier] = newValue
                    service.setVisibility(newValue, for: calendar, member: member,
                                          household: household, in: context)
                })) {
                ForEach(CalendarVisibility.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var groupedSources: [(String, [EKCalendar])] {
        var groups: [(String, [EKCalendar])] = []
        for calendar in calendars {
            let title = calendar.source?.title ?? "Kalender"
            if let index = groups.firstIndex(where: { $0.0 == title }) {
                groups[index].1.append(calendar)
            } else {
                groups.append((title, [calendar]))
            }
        }
        return groups
    }

    private func requestAccess() async {
        _ = await service.requestAccess()
        hasAccess = service.hasFullAccess
        denied = service.accessWasDenied
        reload()
    }

    private func reload() {
        guard hasAccess else { return }
        calendars = service.calendars()
        writable = CalendarExportService.shared.writableCalendars()
        selection = Dictionary(uniqueKeysWithValues: calendars.map {
            ($0.calendarIdentifier, service.visibility(of: $0, member: member, in: context))
        })
        otherImporters = Dictionary(uniqueKeysWithValues: calendars.map {
            ($0.calendarIdentifier, service.otherImporters(of: $0, member: member, in: context))
        })
    }
}
