import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class RuntimePerformanceSettingsTests: XCTestCase {
    func testEnvironment() {
        let cases: [(settings: RuntimePerformanceSettings, expected: [String: String])] = [
            (RuntimePerformanceSettings(), [:]),
            (RuntimePerformanceSettings(showsMetalHUD: true), ["MTL_HUD_ENABLED": "1"]),
            (RuntimePerformanceSettings(graphicsBackend: .metal), [:]),
            (
                RuntimePerformanceSettings(
                    graphicsBackend: .metal,
                    anglePlatformOverrideURL: URL(fileURLWithPath: "/app/Contents/Helpers/libangle-platform-override.dylib")
                ),
                [
                    "DYLD_INSERT_LIBRARIES": "/app/Contents/Helpers/libangle-platform-override.dylib",
                    "MCPELAUNCHER_ANGLE_PLATFORM": "metal"
                ]
            ),
            (
                RuntimePerformanceSettings(
                    graphicsBackend: .vulkan,
                    anglePlatformOverrideURL: URL(fileURLWithPath: "/app/Contents/Helpers/libangle-platform-override.dylib")
                ),
                [:]
            )
        ]
        for testCase in cases {
            XCTAssertEqual(testCase.settings.environment, testCase.expected)
        }
    }

    func testGraphicsEnvironmentSummary() {
        let cases: [(environment: [String: String], expected: String)] = [
            (["PATH": "/bin", "MCPELAUNCHER_GOOGLE_CREDENTIAL_FILE": "/tmp/c.json"], "default"),
            (
                ["MVK_CONFIG_LOG_LEVEL": "2", "MTL_HUD_ENABLED": "1", "PATH": "/bin"],
                "MTL_HUD_ENABLED=1 MVK_CONFIG_LOG_LEVEL=2"
            ),
            (["VK_DRIVER_FILES": "/sdk/driver.json"], "VK_DRIVER_FILES=/sdk/driver.json"),
            (
                ["MCPELAUNCHER_ANGLE_PLATFORM": "metal", "DYLD_INSERT_LIBRARIES": "/x.dylib"],
                "MCPELAUNCHER_ANGLE_PLATFORM=metal"
            )
        ]
        for testCase in cases {
            XCTAssertEqual(RuntimeLauncher.graphicsEnvironmentSummary(testCase.environment), testCase.expected)
        }
    }
}
