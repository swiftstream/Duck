import Duck
import Foundation

private var demoDatabaseDirectory: URL {
    FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
}

extension DatabaseIdentifier {
    static var demo: Self {
        Self(
            path: demoDatabaseDirectory
                .appendingPathComponent("DuckDemo.duckdb")
                .path
        )
    }
}

func prepareDemoDatabase() async throws {
    try FileManager.default.createDirectory(
        at: demoDatabaseDirectory,
        withIntermediateDirectories: true
    )
    try await migrations(.demo)
}
