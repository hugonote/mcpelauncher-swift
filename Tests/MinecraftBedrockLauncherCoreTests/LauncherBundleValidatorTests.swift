import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class LauncherBundleValidatorTests: XCTestCase {
    func testIncompleteWhenARequiredBundleFileIsMissing() throws {
        let temp = try TemporaryDirectory()
        let appURL = temp.url.appendingPathComponent("Launcher.app", isDirectory: true)
        let helpersURL = appURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        XCTAssertFalse(LauncherBundleValidator.isIncomplete(at: temp.url, resourcesAvailable: false))

        for name in LauncherBundleValidator.requiredHelperNames {
            try writeExecutable(helpersURL.appendingPathComponent(name))
        }

        XCTAssertFalse(LauncherBundleValidator.isIncomplete(at: appURL, resourcesAvailable: true))
        XCTAssertTrue(LauncherBundleValidator.isIncomplete(at: appURL, resourcesAvailable: false))

        try FileManager.default.removeItem(at: helpersURL.appendingPathComponent("mcpelauncher-webview"))
        XCTAssertTrue(LauncherBundleValidator.isIncomplete(at: appURL, resourcesAvailable: true))
    }
}
