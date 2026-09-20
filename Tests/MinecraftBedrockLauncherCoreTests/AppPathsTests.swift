import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class AppPathsTests: XCTestCase {
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

    func testDeleteGameFilesRetriesInterruptedDirectoryRemoval() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("AppData", isDirectory: true))
        try paths.ensureDirectories()
        try FileManager.default.createDirectory(
            at: paths.versionsURL.appendingPathComponent("broken/assets", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("asset".utf8).write(
            to: paths.versionsURL.appendingPathComponent("broken/assets/file", isDirectory: false),
            options: .atomic
        )
        try Data("download".utf8).write(
            to: paths.downloadsURL.appendingPathComponent("game.apk", isDirectory: false)
        )
        try Data("[]".utf8).write(to: paths.installedVersionsURL)
        let fileManager = TransientRemoveFailureFileManager(failingURL: paths.versionsURL)

        try paths.deleteGameFiles(fileManager: fileManager)

        XCTAssertEqual(fileManager.failureCount, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.versionsURL.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: paths.downloadsURL.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.installedVersionsURL.path))
    }
}

private final class TransientRemoveFailureFileManager: FileManager, @unchecked Sendable {
    private let failingPath: String
    private(set) var failureCount = 0

    init(failingURL: URL) {
        failingPath = failingURL.path
        super.init()
    }

    override func removeItem(at URL: URL) throws {
        if URL.path == failingPath, failureCount == 0 {
            failureCount += 1
            try super.removeItem(at: URL.appendingPathComponent("broken/assets/file"))
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}
