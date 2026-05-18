import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class GameInstallerTests: XCTestCase {
    func testInstallExtractsMinecraftPayloadOnly() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "zip is required for archive fixture")
        let temp = try TemporaryDirectory()
        let apkURL = try makeAPK(
            in: temp.url,
            name: "minecraft.apk",
            includeManifest: true,
            includeMinecraftLibrary: true
        )
        let versionsURL = temp.url.appendingPathComponent("versions", isDirectory: true)
        let latest = LatestVersion(
            packageName: "com.mojang.minecraftpe",
            versionName: "1.26.20.4",
            versionCode: 126200004,
            isBeta: false
        )

        let installed = try GameInstaller().install(
            apkFiles: [apkURL],
            latestVersion: latest,
            versionsDirectory: versionsURL
        )

        XCTAssertEqual(installed.versionName, "1.26.20.4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.installPath.appendingPathComponent("AndroidManifest.xml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.installPath.appendingPathComponent("assets/example.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.installPath.appendingPathComponent("assets/sound.ogg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.installPath.appendingPathComponent("assets/icon.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.installPath.appendingPathComponent("lib/arm64-v8a/libminecraftpe.so").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.installPath.appendingPathComponent("classes.dex").path))
    }

    func testInstallRejectsAPKWithoutMinecraftLibrary() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "zip is required for archive fixture")
        let temp = try TemporaryDirectory()
        let apkURL = try makeAPK(
            in: temp.url,
            name: "broken.apk",
            includeManifest: true,
            includeMinecraftLibrary: false
        )
        let latest = LatestVersion(packageName: "com.mojang.minecraftpe", versionName: "1.0", versionCode: 1, isBeta: false)

        XCTAssertThrowsError(
            try GameInstaller().install(apkFiles: [apkURL], latestVersion: latest, versionsDirectory: temp.url.appendingPathComponent("versions"))
        ) { error in
            guard case LauncherError.noCompatibleMinecraftLibrary = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeAPK(
        in rootURL: URL,
        name: String,
        includeManifest: Bool,
        includeMinecraftLibrary: Bool
    ) throws -> URL {
        let sourceURL = rootURL.appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        if includeManifest {
            try Data("manifest".utf8).write(to: sourceURL.appendingPathComponent("AndroidManifest.xml"))
        }
        try FileManager.default.createDirectory(at: sourceURL.appendingPathComponent("assets", isDirectory: true), withIntermediateDirectories: true)
        try Data("asset".utf8).write(to: sourceURL.appendingPathComponent("assets/example.txt"))
        try FileManager.default.createDirectory(at: sourceURL.appendingPathComponent("res/raw", isDirectory: true), withIntermediateDirectories: true)
        try Data("sound".utf8).write(to: sourceURL.appendingPathComponent("res/raw/sound.ogg"))
        try FileManager.default.createDirectory(at: sourceURL.appendingPathComponent("res/drawable-xxxhdpi-v4", isDirectory: true), withIntermediateDirectories: true)
        try Data("icon".utf8).write(to: sourceURL.appendingPathComponent("res/drawable-xxxhdpi-v4/icon.png"))
        try FileManager.default.createDirectory(at: sourceURL.appendingPathComponent("lib/arm64-v8a", isDirectory: true), withIntermediateDirectories: true)
        if includeMinecraftLibrary {
            try Data("library".utf8).write(to: sourceURL.appendingPathComponent("lib/arm64-v8a/libminecraftpe.so"))
        }
        try Data("dex".utf8).write(to: sourceURL.appendingPathComponent("classes.dex"))

        let apkURL = rootURL.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qry", apkURL.path, "."]
        process.currentDirectoryURL = sourceURL
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return apkURL
    }
}
