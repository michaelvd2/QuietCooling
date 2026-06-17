// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuietCooling",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuietCoolingShared", targets: ["QuietCoolingShared"]),
        .executable(name: "QuietCooling", targets: ["QuietCooling"])
    ],
    targets: [
        .target(
            name: "QuietCoolingShared",
            path: "Sources/QuietCoolingShared"
        ),
        .executableTarget(
            name: "QuietCooling",
            dependencies: ["QuietCoolingShared"],
            path: "Sources/QuietCooling"
        ),
        .testTarget(
            name: "QuietCoolingTests",
            dependencies: ["QuietCooling", "QuietCoolingShared"],
            path: "Tests/QuietCoolingTests"
        )
    ]
)
