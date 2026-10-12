import UIKitPlus

@MainActor
func demoButton(_ title: String, action: @escaping () -> Void) -> UButton {
    let button = UButton(title)
    #if os(macOS)
    return button.onAction { _ in action() }
    #else
    return button.onTapGesture { action() }
    #endif
}
