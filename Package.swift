// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "edgelesstype",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "edgelesstype", targets: ["OpenTypeless"])
    ],
    targets: [
        .target(name: "OpenTypelessCore"),
        .executableTarget(
            name: "OpenTypeless",
            dependencies: ["OpenTypelessCore"]
        ),
        .testTarget(
            name: "OpenTypelessTests",
            dependencies: ["OpenTypelessCore"]
        )
    ]
)
