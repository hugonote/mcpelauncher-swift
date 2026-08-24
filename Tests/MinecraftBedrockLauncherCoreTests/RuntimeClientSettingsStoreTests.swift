import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class RuntimeClientSettingsStoreTests: XCTestCase {
    func testWritesSettingsFileAndPreservesOtherRuntimeSettings() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let settingsURL = dataURL.appendingPathComponent(RuntimeClientSettingsStore.fileName, isDirectory: false)
        let store = RuntimeClientSettingsStore()

        try store.setInGameStatusBarEnabled(true, dataPath: dataURL)

        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), "enable_menubar=true\n")
        try """
        scale=1.000000
        enable_menubar=true
        enable_fps_hud=0
        vsync=true
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        try store.setInGameStatusBarEnabled(false, dataPath: dataURL)
        try store.setFPSHUDVisibility(.inGame, dataPath: dataURL)
        try store.setVSyncEnabled(false, dataPath: dataURL)

        XCTAssertEqual(
            try String(contentsOf: settingsURL, encoding: .utf8),
            "scale=1.000000\nenable_menubar=false\nenable_fps_hud=2\nvsync=false\n"
        )
    }

    func testReadsSettingsWrittenByRuntime() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let settingsURL = dataURL.appendingPathComponent(RuntimeClientSettingsStore.fileName, isDirectory: false)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try """
        scale=1.000000
        enable_menubar=false
        enable_fps_hud=1
        vsync=false
        """.write(to: settingsURL, atomically: true, encoding: .utf8)
        let store = RuntimeClientSettingsStore()

        XCTAssertEqual(try store.inGameStatusBarEnabled(dataPath: dataURL), false)
        XCTAssertEqual(try store.fpsHUDVisibility(dataPath: dataURL), .always)
        XCTAssertEqual(try store.vSyncEnabled(dataPath: dataURL), false)
    }

    func testMissingSettingsReturnNil() throws {
        let temp = try TemporaryDirectory()
        let dataURL = temp.url.appendingPathComponent("MinecraftData", isDirectory: true)
        let store = RuntimeClientSettingsStore()

        XCTAssertNil(try store.inGameStatusBarEnabled(dataPath: dataURL))
        XCTAssertNil(try store.fpsHUDVisibility(dataPath: dataURL))
        XCTAssertNil(try store.vSyncEnabled(dataPath: dataURL))
    }
}
