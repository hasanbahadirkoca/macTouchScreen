// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TouchRemap",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TouchRemapCore",
            path: "Sources/TouchRemapCore"
        ),
        .executableTarget(
            name: "TouchRemap",
            dependencies: ["TouchRemapCore"],
            path: "Sources/TouchRemap"
        ),
        .testTarget(
            name: "TouchRemapTests",
            dependencies: ["TouchRemapCore"],
            path: "Tests/TouchRemapTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
