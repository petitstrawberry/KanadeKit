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
    ],
    targets: [
        .target(
            name: "KanadeKit",
            dependencies: [.product(name: "Starscream", package: "Starscream")],
            path: "Sources/KanadeKit"
        ),
        .testTarget(
            name: "KanadeKitTests",
            dependencies: ["KanadeKit"],
            path: "Tests/KanadeKitTests"
        ),
    ]
)
