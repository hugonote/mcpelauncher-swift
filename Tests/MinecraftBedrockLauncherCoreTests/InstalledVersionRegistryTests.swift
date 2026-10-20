import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class InstalledVersionRegistryTests: XCTestCase {
    func testUpsertKeepsVersionsSideBySide() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        let registry = InstalledVersionRegistry(paths: paths)
        let older = try makeInstalledVersion(in: paths.versionsURL, name: "1.21.130", code: 100, installedAt: Date(timeIntervalSince1970: 1))
        let newer = try makeInstalledVersion(in: paths.versionsURL, name: "1.26.10", code: 200, installedAt: Date(timeIntervalSince1970: 2))

        try registry.upsert(older)
        let versions = try registry.upsert(newer)

        XCTAssertEqual(versions.map(\.versionName), ["1.26.10", "1.21.130"])
    }

    func testUpsertReplacesVersionWithSameName() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        let registry = InstalledVersionRegistry(paths: paths)
        let original = try makeInstalledVersion(in: paths.versionsURL, name: "1.26.10", code: 200, installedAt: Date(timeIntervalSince1970: 1))
        var reinstalled = original
        reinstalled.installedAt = Date(timeIntervalSince1970: 2)

        try registry.upsert(original)
        let versions = try registry.upsert(reinstalled)

        XCTAssertEqual(versions, [reinstalled])
    }

    func testRemoveDeletesOnlyThatVersion() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        let registry = InstalledVersionRegistry(paths: paths)
        let kept = try makeInstalledVersion(in: paths.versionsURL, name: "1.21.130", code: 100)
        let removed = try makeInstalledVersion(in: paths.versionsURL, name: "1.26.10", code: 200)
        try registry.save([kept, removed])

        let versions = try registry.remove(removed)

        XCTAssertEqual(versions.map(\.versionName), ["1.21.130"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: removed.installPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.installPath.path))
    }

    func testPreferredVersion() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        let registry = InstalledVersionRegistry(paths: paths)
        let older = try makeInstalledVersion(in: paths.versionsURL, name: "1.21.130", code: 100, installedAt: Date(timeIntervalSince1970: 1))
        let newer = try makeInstalledVersion(in: paths.versionsURL, name: "1.26.10", code: 200, installedAt: Date(timeIntervalSince1970: 2))
        try registry.save([older, newer])

        let cases: [(name: String?, expected: String?)] = [
            ("1.21.130", "1.21.130"),
            ("1.26.10", "1.26.10"),
            ("missing", "1.26.10"),
            (nil, "1.26.10")
        ]
        for testCase in cases {
            XCTAssertEqual(try registry.preferredVersion(named: testCase.name)?.versionName, testCase.expected, "\(String(describing: testCase.name))")
        }
    }
}
