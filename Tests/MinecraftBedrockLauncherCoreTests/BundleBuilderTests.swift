import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class BundleBuilderTests: XCTestCase {
    func testBuildCreatesStandaloneAppLayout() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("mcpelauncher-client/mcpelauncher-client")
        try writeExecutable(executableURL)
        let googleHelperURL = temp.url.appendingPathComponent("mcpelauncher-ui-qt", isDirectory: false)
        let webViewHelperURL = temp.url.appendingPathComponent("mcpelauncher-webview", isDirectory: false)
        try writeExecutable(googleHelperURL)
        try writeExecutable(webViewHelperURL)

        let versionURL = temp.url.appendingPathComponent("1.26.20.4", isDirectory: true)
        try FileManager.default.createDirectory(
            at: versionURL.appendingPathComponent("lib/arm64-v8a", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("manifest".utf8).write(to: versionURL.appendingPathComponent("AndroidManifest.xml"))
        try Data("library".utf8).write(to: versionURL.appendingPathComponent("lib/arm64-v8a/libminecraftpe.so"))

        let outputDirectory = temp.url.appendingPathComponent("export", isDirectory: true)
        let spec = BundleSpec(
            appName: "Minecraft Bedrock",
            bundleIdentifier: "local.minecraft.bedrock.mcpelauncher",
            version: "1.26.20.4",
            runtimePath: runtimeURL,
            gameVersionPath: versionURL,
            outputPath: outputDirectory,
            googleCredentialsHelperPath: googleHelperURL,
            webViewHelperPath: webViewHelperURL
        )

        let appURL = try BundleBuilder().build(spec: spec)

        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Contents/Info.plist").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: appURL.appendingPathComponent("Contents/MacOS/MinecraftBedrock").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: appURL.appendingPathComponent("Contents/Helpers/mcpelauncher-ui-qt").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: appURL.appendingPathComponent("Contents/Helpers/mcpelauncher-webview").path))
        let runScriptURL = appURL.appendingPathComponent("Contents/Resources/Minecraft Bedrock/run-minecraft-1.26.20.4.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: runScriptURL.path))
        let runScript = try String(contentsOf: runScriptURL)
        XCTAssertTrue(runScript.contains("--disable-fmod -fes -dg"))
        XCTAssertTrue(runScript.contains("Resources/Minecraft Bedrock/mcpelauncher-client/mcpelauncher-client"))
        XCTAssertFalse(runScript.contains("-dd"))
        XCTAssertFalse(runScript.contains("-dc"))
        XCTAssertFalse(runScript.contains("-m \"$PATCH_DIR\""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Contents/Resources/Minecraft Bedrock/game-versions/1.26.20.4/lib/arm64-v8a/libminecraftpe.so").path))
    }

    func testBuildFailsWhenRuntimeExecutableIsMissing() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("runtime", isDirectory: true)
        let versionURL = temp.url.appendingPathComponent("1.0", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)

        let spec = BundleSpec(
            appName: "Minecraft Bedrock",
            bundleIdentifier: "local.minecraft.bedrock.mcpelauncher",
            version: "1.0",
            runtimePath: runtimeURL,
            gameVersionPath: versionURL,
            outputPath: temp.url
        )

        XCTAssertThrowsError(try BundleBuilder().build(spec: spec)) { error in
            guard case LauncherError.missingRuntimeExecutable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
