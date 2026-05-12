// swift-tools-version: 5.10
import Foundation
import PackageDescription

/// Embedded via `-sectcreate __TEXT __info_plist` so the binary carries privacy keys (`NSSpeechRecognitionUsageDescription`).
/// Plain `swift run` / default debug signing still omits the Speech entitlement from the ad-hoc signature — use
/// `scripts/run-with-speech-capability.sh` or `swift package plugin run-with-speech --allow-writing-to-package-directory`.
private let embeddedInfoPlistPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Abscido/Info.plist")
    .path

let package = Package(
    name: "Abscido",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Abscido", targets: ["Abscido"]),
        .plugin(name: "RunWithSpeech", targets: ["RunWithSpeech"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.0"),
        .package(url: "https://github.com/OpenTimelineIO/OpenTimelineIO-Swift-Bindings.git", branch: "main"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "Abscido",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "OpenTimelineIO", package: "OpenTimelineIO-Swift-Bindings"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Abscido",
            exclude: [
                "Abscido.entitlements",
                "LocalSigning.entitlements",
                "Info.plist",
            ],
            resources: [
                .copy("Resources/scripts"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", embeddedInfoPlistPath,
                ]),
            ]
        ),
        .plugin(
            name: "RunWithSpeech",
            capability: .command(
                intent: .custom(
                    verb: "run-with-speech",
                    description: "Build Abscido, apply Speech recognition entitlements, and launch"
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Re-sign the SwiftPM binary with LocalSigning.entitlements (required for Apple Speech / TCC)."),
                ]
            ),
            path: "Plugins/RunWithSpeech"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
