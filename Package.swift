// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RimlightCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RimlightCore", targets: ["RimlightCore"]),
        .library(name: "RimlightCommand", targets: ["RimlightCommand"]),
        .executable(name: "rimlight", targets: ["rimlight"]),
    ],
    targets: [
        // Shared by the app and the `rimlight` CLI. Nonisolated by default (no
        // defaultIsolation(MainActor)) and never imports AppKit or UIKit.
        .target(
            name: "RimlightCore",
            resources: [
                .copy("Resources/Instructions.md"),
                .copy("Resources/Design.md"),
                .copy("Resources/Adaptive.md"),
                .copy("Resources/Build.md"),
                .copy("Resources/Styles"),
                .copy("Resources/TileMask.png"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The `rimlight` command. Only `RimlightCommand.main` is public, so the app's Xcode
        // target can embed the same command as a one-line shim.
        .target(
            name: "RimlightCommand",
            dependencies: ["RimlightCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "rimlight",
            dependencies: ["RimlightCommand"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RimlightCoreTests",
            // RimlightCommand for the build's draw plan and its options, which live in the command
            dependencies: ["RimlightCore", "RimlightCommand"],
            // One real `codex exec --json` stdout for the event parser. The golden SKILL.md,
            // build.md and styles are the committed `skills/rimlight/`.
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
