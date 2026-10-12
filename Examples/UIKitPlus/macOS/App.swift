#if os(macOS)
import AppKit
import UIKitPlus

@main
final class App: UIKitPlus.App {
    private lazy var mainController = MainViewController()
    private lazy var shellWindow = Window { [self] in mainController }

    @AppBuilder override var body: AppBuilderContent {
        shellWindow.title("Duck UIKitPlus Demo")
            .size(1100, 850)
            .minSize(.init(width: 760, height: 620))
            .center()
            .makeKeyAndOrderFront()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainController.shutdown()
    }
}
#endif
