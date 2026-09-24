import SwiftUI
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

    private var service: CalendarImportService { .shared }

    var body: some View {
        List {
            if !hasAccess {
                Section {
                    Text("Wählen Sie danach für jeden Kalender, ob die Familie Termine mit Titel, nur als „Belegt“ oder gar nicht sieht. Neue Kalender stehen immer auf „Nicht übernehmen“.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if denied {
                        Text("Der Zugriff wurde abgelehnt. Sie können ihn in den iPhone-Einstellungen unter Apps → Family Planner → Kalender erlauben.")
                            .font(.footnote)
                    } else {
                        Button("Zugriff auf Kalender erlauben") {
                            Task { await requestAccess() }
                        }
                    }
                }
            } else {
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
                    Text("„Nur als Belegtzeit“: Titel, Ort und Notizen bleiben auf diesem iPhone. Ganztägige Termine werden vorerst nicht übernommen. Übernommen wird eine Woche zurück bis drei Monate voraus.")
                }
            }
        }
        .navigationTitle("Meine Kalender")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func row(for calendar: EKCalendar) -> some View {
        HStack(spacing: Spacing.m) {
            // Farbe des Kalenders aus dem System, kein eigener Farbwert der App.
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 10, height: 10)
            Text(calendar.title)
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
        selection = Dictionary(uniqueKeysWithValues: calendars.map {
            ($0.calendarIdentifier, service.visibility(of: $0, member: member, in: context))
        })
    }
}
