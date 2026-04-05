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
    dependencies: [],
    targets: [
        .target(
            name: "KanadeKit",
            path: "Sources/KanadeKit"
        ),
        .testTarget(
            name: "KanadeKitTests",
            dependencies: ["KanadeKit"],
            path: "Tests/KanadeKitTests"
        ),
    ]
)
