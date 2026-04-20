// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Abscido",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.0"),
        // OpenTimelineIO Swift bindings — add when available for your build environment:
        // .package(url: "https://github.com/OpenTimelineIO/OpenTimelineIO-Swift-Bindings", from: "0.17.0"),
    ],
    targets: [
        .executableTarget(
            name: "Abscido",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Abscido",
            exclude: [
                "Abscido.entitlements",
            ],
            resources: [
                .copy("Resources/scripts"),
            ]
        )
    ]
)
