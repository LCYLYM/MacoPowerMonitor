// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacoPowerMonitor",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "MacoPowerMonitor",
            targets: ["MacoPowerMonitor"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "MacoPowerMonitor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
