import CoreData
import Foundation

/// Nur für Xcode-Previews, den Simulator und die App-Store-Bildschirmfotos (`-sampleData`
/// im Testmodus, Speicher nur im Arbeitsspeicher). Wird nie in einen Cloud-Store geschrieben.
/// Frei erfundene Namen, keine echten Familiendaten.
enum SampleData {

    static func populate(in context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func time(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }

        guard let household = try? HouseholdService.bootstrapIfNeeded(
            in: context,
            householdName: "Familie Muster",
            ownerDisplayName: "Tom",
            ownerShortName: "To") else { return }

        let owner = (household.members as? Set<CDMember>)?.first
        let partner = HouseholdService.makeMember(in: context, household: household,
                                                  displayName: "Anna", shortName: "An",
                                                  role: .adult, accountKind: .participant,
                                                  colorToken: "person2", sortIndex: 1)
        let kid1 = HouseholdService.makeMember(in: context, household: household,
                                               displayName: "Leon", shortName: "Le",
                                               role: .child, accountKind: .managed,
                                               colorToken: "person3", sortIndex: 2)
        let kid2 = HouseholdService.makeMember(in: context, household: household,
                                               displayName: "Mia", shortName: "Mi",
                                               role: .child, accountKind: .managed,
                                               colorToken: "person4", sortIndex: 3)

        guard let owner else { return }
        let tags = (household.tags as? Set<CDTag>) ?? []
        func tag(_ name: String) -> CDTag? { tags.first { $0.name == name } }

        EventService.makeEvent(in: context, household: household,
                               title: "Belegt", startAt: time(9), endAt: time(12),
                               createdBy: owner, subjects: [owner],
                               visibility: .busyOnly, tag: tag("Arbeit"))

        EventService.makeEvent(in: context, household: household,
                               title: "Schule", startAt: time(8), endAt: time(13),
                               createdBy: owner, subjects: [kid1, kid2],
                               tag: tag("Schule"), locationName: "Grundschule")

        EventService.makeEvent(in: context, household: household,
                               title: "Schwimmkurs", startAt: time(17), endAt: time(18),
                               createdBy: owner, subjects: [kid1],
                               requiredRoles: [.driveTo, .driveFrom],
                               tag: tag("Sport"), locationName: "Schwimmbad")

        EventService.makeEvent(in: context, household: household,
                               title: "Kinderarzt", startAt: time(16, 30), endAt: time(17, 15),
                               createdBy: owner, subjects: [kid2],
                               requiredRoles: [.accompany],
                               tag: tag("Arzt"), locationName: "Kinderarztpraxis")

        EventService.makeEvent(in: context, household: household,
                               title: "Homeoffice", startAt: time(9), endAt: time(17),
                               createdBy: owner, subjects: [partner],
                               kind: .statusBlock, tag: tag("Arbeit"))

        // Weitere Tage für Woche und Monat
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let d = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }
        // Werktage der laufenden Woche füllen, egal auf welchen Tag "heute" fällt. Sonst
        // bleibt die Wochenansicht der Bildschirmfotos an einem Samstag fast leer (10.10.2026).
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let afternoon: [(title: String, hour: Int, minute: Int, endHour: Int, endMinute: Int,
                         who: [CDMember], roles: [ParticipationRole], tag: String?)] = [
            ("Fußball", 16, 0, 17, 30, [kid1], [.driveFrom], "Sport"),
            ("Klavier", 15, 0, 16, 0, [kid2], [.driveTo], nil),
            ("Elternabend", 19, 0, 20, 30, [owner, partner], [], nil),
            ("Turnen", 15, 30, 16, 30, [kid2], [.driveFrom], "Sport"),
            ("Bücherei", 14, 0, 15, 0, [kid1, partner], [], nil),
        ]
        for index in 0..<5 {
            guard let date = calendar.date(byAdding: .day, value: index, to: weekStart),
                  !calendar.isDate(date, inSameDayAs: today) else { continue }
            func at(_ hour: Int, _ minute: Int = 0) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
            }
            EventService.makeEvent(in: context, household: household,
                                   title: "Schule", startAt: at(8), endAt: at(13),
                                   createdBy: owner, subjects: [kid1, kid2],
                                   tag: tag("Schule"), locationName: "Grundschule")
            EventService.makeEvent(in: context, household: household,
                                   title: "Belegt", startAt: at(9), endAt: at(15),
                                   createdBy: owner, subjects: [owner],
                                   visibility: .busyOnly, tag: tag("Arbeit"))
            let item = afternoon[index]
            EventService.makeEvent(in: context, household: household,
                                   title: item.title,
                                   startAt: at(item.hour, item.minute),
                                   endAt: at(item.endHour, item.endMinute),
                                   createdBy: owner, subjects: item.who,
                                   requiredRoles: item.roles,
                                   tag: item.tag.flatMap(tag))
        }
        EventService.makeEvent(in: context, household: household,
                               title: "Oma besuchen", startAt: day(5, 14), endAt: day(5, 18),
                               createdBy: owner, subjects: [owner, partner, kid1, kid2])
        EventService.makeEvent(in: context, household: household,
                               title: "Klassenfahrt", startAt: day(8, 0), endAt: day(11, 0),
                               createdBy: owner, subjects: [kid1], isAllDay: true)

        try? context.save()
    }

    /// Bildschirmfotos: Beispielhaushalt anlegen und dieses Gerät als ersten Erwachsenen setzen.
    static func populateForScreenshots(in context: NSManagedObjectContext) {
        populate(in: context)
        if let household = try? HouseholdService.fetchHousehold(in: context),
           let owner = household.ownerMemberID {
            UserDefaults.standard.set(owner.uuidString, forKey: CurrentMember.storageKey)
        }
    }
}
