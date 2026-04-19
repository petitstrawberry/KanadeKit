// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KanadeKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "KanadeKit",
            targets: ["KanadeKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.8"),
        .package(url: "https://github.com/sbooth/flac-binary-xcframework", from: "0.2.0"),
        .package(url: "https://github.com/sbooth/ogg-binary-xcframework", from: "0.1.3"),
    ],
    targets: [
        .target(
            name: "KanadeKit",
            dependencies: [
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "FLAC", package: "flac-binary-xcframework"),
                .product(name: "ogg", package: "ogg-binary-xcframework"),
            ],
            path: "Sources/KanadeKit"
        ),
        .testTarget(
            name: "KanadeKitTests",
            dependencies: ["KanadeKit"],
            path: "Tests/KanadeKitTests"
        ),
    ]
)
