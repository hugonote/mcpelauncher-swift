import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class RuntimeClientSettingsStoreTests: XCTestCase {
    func testCreatesSettingsFileWhenDataDirectoryDoesNotExist() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)

        try RuntimeClientSettingsStore().setInGameStatusBarEnabled(true, dataPath: dataURL)

        let settingsURL = dataURL.appendingPathComponent("mcpelauncher-client-settings.txt", isDirectory: false)
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), "enable_menubar=true\n")
    }

    func testUpdatesStatusBarSettingAndPreservesOtherRuntimeSettings() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let settingsURL = dataURL.appendingPathComponent("mcpelauncher-client-settings.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try """
        scale=1.000000
        enable_menubar=true
        vsync=true
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        try RuntimeClientSettingsStore().setInGameStatusBarEnabled(false, dataPath: dataURL)

        XCTAssertEqual(
            try String(contentsOf: settingsURL, encoding: .utf8),
            "scale=1.000000\nenable_menubar=false\nvsync=true\n"
        )
    }

    func testReadsStatusBarSettingWrittenByRuntime() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let settingsURL = dataURL.appendingPathComponent("mcpelauncher-client-settings.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try """
        scale=1.000000
        enable_menubar=false
        vsync=true
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        let isEnabled = try RuntimeClientSettingsStore().inGameStatusBarEnabled(dataPath: dataURL)

        XCTAssertEqual(isEnabled, false)
    }

    func testUpdatesFPSHUDVisibilityAndPreservesOtherRuntimeSettings() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let settingsURL = dataURL.appendingPathComponent("mcpelauncher-client-settings.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try """
        scale=1.000000
        enable_fps_hud=0
        vsync=true
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        try RuntimeClientSettingsStore().setFPSHUDVisibility(.inGame, dataPath: dataURL)

        XCTAssertEqual(
            try String(contentsOf: settingsURL, encoding: .utf8),
            "scale=1.000000\nenable_fps_hud=2\nvsync=true\n"
        )
    }

    func testReadsFPSHUDVisibilityWrittenByRuntime() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let settingsURL = dataURL.appendingPathComponent("mcpelauncher-client-settings.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try """
        scale=1.000000
        enable_fps_hud=1
        vsync=true
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        let visibility = try RuntimeClientSettingsStore().fpsHUDVisibility(dataPath: dataURL)

        XCTAssertEqual(visibility, .always)
    }

    func testUpdatesVSyncSettingAndPreservesOtherRuntimeSettings() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let settingsURL = dataURL.appendingPathComponent("mcpelauncher-client-settings.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try """
        scale=1.000000
        vsync=true
        enable_fps_hud=0
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        try RuntimeClientSettingsStore().setVSyncEnabled(false, dataPath: dataURL)

        XCTAssertEqual(
            try String(contentsOf: settingsURL, encoding: .utf8),
            "scale=1.000000\nvsync=false\nenable_fps_hud=0\n"
        )
    }

    func testReadsVSyncSettingWrittenByRuntime() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let settingsURL = dataURL.appendingPathComponent("mcpelauncher-client-settings.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try """
        scale=1.000000
        vsync=false
        enable_fps_hud=0
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        let isEnabled = try RuntimeClientSettingsStore().vSyncEnabled(dataPath: dataURL)

        XCTAssertEqual(isEnabled, false)
    }

    func testMissingStatusBarSettingReturnsNil() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)

        let isEnabled = try RuntimeClientSettingsStore().inGameStatusBarEnabled(dataPath: dataURL)

        XCTAssertNil(isEnabled)
    }

    func testMissingFPSHUDVisibilityReturnsNil() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)

        let visibility = try RuntimeClientSettingsStore().fpsHUDVisibility(dataPath: dataURL)

        XCTAssertNil(visibility)
    }

    func testMissingVSyncSettingReturnsNil() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)

        let isEnabled = try RuntimeClientSettingsStore().vSyncEnabled(dataPath: dataURL)

        XCTAssertNil(isEnabled)
    }
}
