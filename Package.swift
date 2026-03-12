// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AeroOverlay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AeroOverlay",
            path: "Sources/AeroOverlay",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
