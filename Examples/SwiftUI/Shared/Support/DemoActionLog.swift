import Combine
import Foundation

@MainActor
final class DemoActionLog: ObservableObject {
    @Published private(set) var entries: [String] = []
    func record(_ feature: String, _ action: String, _ result: String) {
        entries.insert("\(Date.now.formatted(date: .omitted, time: .standard)) · \(feature) · \(action): \(result)", at: 0)
        entries = Array(entries.prefix(100))
    }
}
