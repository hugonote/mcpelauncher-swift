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
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.helperStateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.logsURL.path))
    }
}
