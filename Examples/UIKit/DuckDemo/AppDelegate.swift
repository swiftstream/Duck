import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func prepareDatabase() async throws {
        try await prepareDemoDatabase()
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}
