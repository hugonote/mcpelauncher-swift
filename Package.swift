// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLauncher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MinecraftBedrockLauncher",
            targets: ["MinecraftBedrockLauncher"]
        ),
        .executable(
            name: "mcpelauncher-ui-qt",
            targets: ["GoogleCredentialsHelper"]
        ),
        .executable(
            name: "mcpelauncher-webview",
            targets: ["MinecraftBedrockWebView"]
        ),
        .library(
            name: "MinecraftBedrockLauncherCore",
            targets: ["MinecraftBedrockLauncherCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .target(
            name: "MinecraftBedrockLauncherCore"
        ),
        .executableTarget(
            name: "MinecraftBedrockLauncher",
            dependencies: [
                "MinecraftBedrockLauncherCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "GoogleCredentialsHelper",
            dependencies: ["MinecraftBedrockLauncherCore"]
        ),
        .executableTarget(
            name: "MinecraftBedrockWebView"
        ),
        .testTarget(
            name: "MinecraftBedrockLauncherCoreTests",
            dependencies: ["MinecraftBedrockLauncherCore"]
        )
    ]
)
