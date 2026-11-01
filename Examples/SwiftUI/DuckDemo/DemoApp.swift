import SwiftUI

@main
struct DemoApp: App {
    @State private var isReady = false
    @State private var preparationError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    ContentView()
                } else if let preparationError {
                    Text(preparationError)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ProgressView()
                }
            }
            .task {
                guard !isReady, preparationError == nil else { return }

                do {
                    try await prepareDemoDatabase()
                    isReady = true
                } catch {
                    preparationError = String(describing: error)
                }
            }
        }
    }
}
