import CloudKit
import CoreData
import UIKit
import UserNotifications
import os

/// Annahme einer Einladung.
///
/// Tippt ein Familienmitglied auf den Einladungslink, übergibt iOS die
/// `CKShare.Metadata` an den Scene-Delegate – bei laufender App über
/// `windowScene(_:userDidAcceptCloudKitShareWith:)`, bei kaltem Start über die
/// `connectionOptions`. Beide Wege enden hier.
enum ShareAcceptance {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Familienplaner",
                                       category: "Sharing")

    @MainActor
    static func accept(_ metadata: CKShare.Metadata,
                       persistence: PersistenceController = .shared) async {
        guard let sharedStore = persistence.sharedStore else {
            logger.error("Geteilter Store fehlt, Einladung kann nicht angenommen werden")
            return
        }
        do {
            _ = try await persistence.container.acceptShareInvitations(from: [metadata], into: sharedStore)
            NotificationCenter.default.post(name: .householdShareAccepted, object: nil)
        } catch {
            logger.error("Einladung konnte nicht angenommen werden: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - App- und Scene-Delegate

/// SwiftUI bietet keinen eigenen Einstieg für CloudKit-Einladungen.
/// Deshalb ein schlanker Scene-Delegate, der nur diese eine Aufgabe hat.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Stille Mitteilungen von CloudKit empfangen: So erfährt die App auch im
        // Hintergrund von Änderungen anderer Familienmitglieder (Hintergrundabgleich).
        application.registerForRemoteNotifications()
        return true
    }

    /// Erinnerungen auch zeigen, wenn die App gerade offen ist.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Angetippte Erinnerung öffnet den passenden Tag.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let stamp = info[ReminderService.dayKey] as? Double else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .openDayFromReminder, object: nil,
                                            userInfo: ["day": Date(timeIntervalSince1970: stamp)])
        }
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in await ShareAcceptance.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in await ShareAcceptance.accept(cloudKitShareMetadata) }
    }
}
