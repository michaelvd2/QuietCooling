// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuietCooling",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "QuietCooling", targets: ["QuietCooling"])
    ],
    targets: [
        .executableTarget(
            name: "QuietCooling",
            path: "Sources/QuietCooling"
        ),
        .testTarget(
            name: "QuietCoolingTests",
            dependencies: ["QuietCooling"],
            path: "Tests/QuietCoolingTests"
        )
    ]
)
