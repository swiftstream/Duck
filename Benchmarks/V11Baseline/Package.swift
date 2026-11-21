// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "DuckV11Baseline",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "DuckV11Baseline", targets: ["DuckV11Baseline"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DuckV11Baseline",
            dependencies: [
                .product(name: "Duck", package: "Duck")
            ]
        )
    ]
)
