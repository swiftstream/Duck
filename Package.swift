// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SwiftDuckDB",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SwiftDuckDB",
            targets: ["SwiftDuckDB"]
        )
    ],
    targets: [
        .target(name: "SwiftDuckDB")
    ],
    swiftLanguageModes: [.v6]
)
