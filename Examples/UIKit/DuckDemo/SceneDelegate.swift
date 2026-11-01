import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard
            let appDelegate = unsafe UIApplication.shared.delegate as? AppDelegate,
            let navigationController = window?.rootViewController as? UINavigationController,
            let viewController = navigationController.topViewController as? ViewController
        else {
            return
        }

        viewController.loadViewIfNeeded()

        Task {
            do {
                try await appDelegate.prepareDatabase()
                viewController.start()
            } catch {
                viewController.show(error: error)
            }
        }
    }
}
