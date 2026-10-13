// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "edgelesstype",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "edgelesstype", targets: ["EdgelessType"]),
        .executable(name: "edgelesstype-data-migrate", targets: ["EdgelessTypeMigration"])
    ],
    targets: [
        .target(name: "EdgelessTypeCore"),
        .executableTarget(
            name: "EdgelessType",
            dependencies: ["EdgelessTypeCore"]
        ),
        .executableTarget(name: "EdgelessTypeMigration", dependencies: ["EdgelessTypeCore"]),
        .testTarget(
            name: "EdgelessTypeTests",
            dependencies: ["EdgelessTypeCore"]
        )
    ]
)
