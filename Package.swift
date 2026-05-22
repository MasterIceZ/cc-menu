// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "cc-menu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "cc-menu",
            path: "Sources/cc-menu",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
