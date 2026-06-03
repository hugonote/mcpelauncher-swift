import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class InstalledVersionRegistryTests: XCTestCase {
    func testLoadReturnsInstalledVersionWhenPayloadExists() throws {
        let temp = try TemporaryDirectory()
        let registryURL = temp.url.appendingPathComponent("versions.json", isDirectory: false)
        let installURL = temp.url.appendingPathComponent("game-versions/1.26.20.4", isDirectory: true)
        try makeInstalledPayload(at: installURL)
        let version = InstalledVersion(
            versionName: "1.26.20.4",
            versionCode: 972602004,
            installPath: installURL,
            installedAt: Date(timeIntervalSince1970: 2)
        )
        let registry = InstalledVersionRegistry(registryURL: registryURL)
        try registry.save([version])

        XCTAssertEqual(try registry.load(), [version])
    }

    func testLoadIgnoresVersionWhenInstallDirectoryIsMissing() throws {
        let temp = try TemporaryDirectory()
        let registryURL = temp.url.appendingPathComponent("versions.json", isDirectory: false)
        let missingURL = temp.url.appendingPathComponent("game-versions/1.26.10.4", isDirectory: true)
        let version = InstalledVersion(
            versionName: "1.26.10.4",
            versionCode: 972601004,
            installPath: missingURL
        )
        let registry = InstalledVersionRegistry(registryURL: registryURL)
        try registry.save([version])

        XCTAssertEqual(try registry.load(), [])
    }

    func testLoadIgnoresVersionWhenRequiredPayloadIsMissing() throws {
        let temp = try TemporaryDirectory()
        let registryURL = temp.url.appendingPathComponent("versions.json", isDirectory: false)
        let installURL = temp.url.appendingPathComponent("game-versions/1.26.10.4", isDirectory: true)
        try FileManager.default.createDirectory(at: installURL, withIntermediateDirectories: true)
        let version = InstalledVersion(
            versionName: "1.26.10.4",
            versionCode: 972601004,
            installPath: installURL
        )
        let registry = InstalledVersionRegistry(registryURL: registryURL)
        try registry.save([version])

        XCTAssertEqual(try registry.load(), [])
    }

    func testLoadKeepsValidVersionsWhenOtherEntriesAreBroken() throws {
        let temp = try TemporaryDirectory()
        let registryURL = temp.url.appendingPathComponent("versions.json", isDirectory: false)
        let validURL = temp.url.appendingPathComponent("game-versions/1.26.20.4", isDirectory: true)
        let missingURL = temp.url.appendingPathComponent("game-versions/1.26.10.4", isDirectory: true)
        try makeInstalledPayload(at: validURL)
        let valid = InstalledVersion(
            versionName: "1.26.20.4",
            versionCode: 972602004,
            installPath: validURL,
            installedAt: Date(timeIntervalSince1970: 1)
        )
        let broken = InstalledVersion(
            versionName: "1.26.10.4",
            versionCode: 972601004,
            installPath: missingURL,
            installedAt: Date(timeIntervalSince1970: 2)
        )
        let registry = InstalledVersionRegistry(registryURL: registryURL)
        try registry.save([broken, valid])

        XCTAssertEqual(try registry.load(), [valid])
    }

    private func makeInstalledPayload(at installURL: URL) throws {
        try FileManager.default.createDirectory(
            at: installURL.appendingPathComponent("lib/arm64-v8a", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("manifest".utf8).write(to: installURL.appendingPathComponent("AndroidManifest.xml", isDirectory: false))
        try Data("library".utf8).write(
            to: installURL
                .appendingPathComponent("lib", isDirectory: true)
                .appendingPathComponent("arm64-v8a", isDirectory: true)
                .appendingPathComponent("libminecraftpe.so", isDirectory: false)
        )
    }
}
