// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SeedBox",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SeedBox", targets: ["SeedBox"]),
        .library(name: "SeedBoxCore", targets: ["SeedBoxCore"])
    ],
    targets: [
        .target(name: "SeedBoxCore"),
        .executableTarget(
            name: "SeedBox",
            dependencies: ["SeedBoxCore"],
            resources: [
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "SeedBoxCoreTests",
            dependencies: ["SeedBoxCore"]
        )
    ]
)
