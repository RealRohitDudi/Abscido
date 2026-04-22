// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Abscido",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.0"),
        .package(url: "https://github.com/OpenTimelineIO/OpenTimelineIO-Swift-Bindings.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Abscido",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "OpenTimelineIO", package: "OpenTimelineIO-Swift-Bindings"),
            ],
            path: "Abscido",
            exclude: [
                "Abscido.entitlements",
            ],
            resources: [
                .copy("Resources/scripts"),
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
