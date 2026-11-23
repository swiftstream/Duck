// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "DuckV11Wave03B",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "DuckV11Wave03B", targets: ["DuckV11Wave03B"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DuckV11Wave03B",
            dependencies: [
                .product(name: "Duck", package: "Duck")
            ]
        )
    ]
)
