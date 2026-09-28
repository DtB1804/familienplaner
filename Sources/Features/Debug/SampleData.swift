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
        EventService.makeEvent(in: context, household: household,
                               title: "Fußball", startAt: day(1, 16), endAt: day(1, 17, 30),
                               createdBy: owner, subjects: [kid1],
                               requiredRoles: [.driveFrom], tag: tag("Sport"))
        EventService.makeEvent(in: context, household: household,
                               title: "Elternabend", startAt: day(2, 19), endAt: day(2, 20, 30),
                               createdBy: owner, subjects: [owner, partner], locationName: "Grundschule")
        EventService.makeEvent(in: context, household: household,
                               title: "Klavier", startAt: day(3, 15), endAt: day(3, 16),
                               createdBy: owner, subjects: [kid2], requiredRoles: [.driveTo])
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
