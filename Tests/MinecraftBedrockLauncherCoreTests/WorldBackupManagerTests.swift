import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class WorldBackupManagerTests: XCTestCase {
    func testBackupOnlyWhenLaunchingOlderVersion() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        try writeWorld(named: "Survival", paths: paths)
        let manager = WorldBackupManager(paths: paths)
        let newer = try makeInstalledVersion(in: paths.versionsURL, name: "1.26.10", code: 200)
        let older = try makeInstalledVersion(in: paths.versionsURL, name: "1.21.130", code: 100)

        XCTAssertNil(try manager.backupWorldsIfDowngrading(to: newer))
        try manager.recordLaunch(of: newer)
        XCTAssertNil(try manager.backupWorldsIfDowngrading(to: newer))

        let backupURL = try XCTUnwrap(try manager.backupWorldsIfDowngrading(to: older))

        XCTAssertTrue(backupURL.lastPathComponent.hasSuffix("1.26.10 to 1.21.130"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("minecraftWorlds/Survival/level.dat").path
        ))
    }

    func testNoBackupWithoutWorlds() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        let manager = WorldBackupManager(paths: paths)
        try manager.recordLaunch(of: try makeInstalledVersion(in: paths.versionsURL, name: "1.26.10", code: 200))

        XCTAssertNil(try manager.backupWorldsIfDowngrading(to: try makeInstalledVersion(in: paths.versionsURL, name: "1.21.130", code: 100)))
    }

    func testOldBackupsArePruned() throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url)
        try writeWorld(named: "Creative", paths: paths)
        let clock = TestClock()
        let manager = WorldBackupManager(paths: paths, maximumBackupCount: 2, now: { clock.tick() })
        let newer = try makeInstalledVersion(in: paths.versionsURL, name: "1.26.10", code: 200)
        let older = try makeInstalledVersion(in: paths.versionsURL, name: "1.21.130", code: 100)

        for _ in 0..<3 {
            try manager.recordLaunch(of: newer)
            try manager.backupWorldsIfDowngrading(to: older)
        }

        XCTAssertEqual(try manager.backups().count, 2)
    }

    private func writeWorld(named name: String, paths: AppPaths) throws {
        let worldURL = paths.minecraftWorldsURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: worldURL, withIntermediateDirectories: true)
        try Data("level".utf8).write(to: worldURL.appendingPathComponent("level.dat"))
    }
}

private final class TestClock: @unchecked Sendable {
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    func tick() -> Date {
        current = current.addingTimeInterval(60)
        return current
    }
}
