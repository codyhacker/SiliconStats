// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiliconStats",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SiliconStats",
            path: "Sources/SiliconStats",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
