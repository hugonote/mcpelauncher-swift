import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class AppPathsTests: XCTestCase {
    func testEnsureDirectoriesCreatesExpectedLayout() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("AppData", isDirectory: true))

        try paths.ensureDirectories()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.baseURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.downloadsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.versionsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.runtimeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.logsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: paths.baseURL.appendingPathComponent("MinecraftCache", isDirectory: true).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.legacyGooglePlayStateURL.path))
    }

    func testRemoveLegacyGooglePlayStateDeletesPlaintextTokenCacheAndFileDeviceState() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("AppData", isDirectory: true))
        try paths.ensureDirectories()
        try FileManager.default.createDirectory(
            at: paths.legacyGooglePlayStateURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )

        let legacyFiles = ["device.conf", "device.conf.state", "playdl.conf", "token_cache.conf", ".DS_Store"].map {
            paths.legacyGooglePlayStateURL.appendingPathComponent($0, isDirectory: false)
        }
        for url in legacyFiles {
            try Data("secret=true".utf8).write(to: url)
        }
        let finskyDirectory = paths.legacyGooglePlayStateURL.appendingPathComponent("finsky-devices", isDirectory: true)
        try FileManager.default.createDirectory(at: finskyDirectory, withIntermediateDirectories: true)
        try Data("device-token=true".utf8).write(to: finskyDirectory.appendingPathComponent("device.json", isDirectory: false))

        try paths.removeLegacyGooglePlayState()

        for url in legacyFiles {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: finskyDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.legacyGooglePlayStateURL.path))
    }

    func testRemoveStaleGameInstallDirectoriesDeletesHiddenInstallWorkDirectoriesOnly() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("AppData", isDirectory: true))
        try paths.ensureDirectories()

        let staleInstallURL = paths.versionsURL.appendingPathComponent(".install-broken", isDirectory: true)
        let installedVersionURL = paths.versionsURL.appendingPathComponent("1.26.20.4", isDirectory: true)
        let otherHiddenURL = paths.versionsURL.appendingPathComponent(".not-an-install", isDirectory: true)
        try FileManager.default.createDirectory(at: staleInstallURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installedVersionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherHiddenURL, withIntermediateDirectories: true)

        try paths.removeStaleGameInstallDirectories()

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleInstallURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedVersionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherHiddenURL.path))
    }
}
