// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuietCooling",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuietCoolingShared", targets: ["QuietCoolingShared"]),
        .executable(name: "QuietCooling", targets: ["QuietCooling"]),
        .executable(name: "QuietCoolingHelper", targets: ["QuietCoolingHelper"])
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
        .target(
            name: "QuietCoolingHelperCore",
            dependencies: ["QuietCoolingShared"],
            path: "Sources/QuietCoolingHelperCore"
        ),
        .executableTarget(
            name: "QuietCoolingHelper",
            dependencies: ["QuietCoolingHelperCore"],
            path: "Sources/QuietCoolingHelper"
        ),
        .testTarget(
            name: "QuietCoolingTests",
            dependencies: ["QuietCooling", "QuietCoolingHelperCore", "QuietCoolingShared"],
            path: "Tests/QuietCoolingTests"
        )
    ]
)
