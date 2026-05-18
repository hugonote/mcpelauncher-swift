import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class CompatibilityPatchManagerTests: XCTestCase {
    func testModDBVersionAllowsMissingExtraVersions() throws {
        let data = Data(
            """
            {
              "version": "0.0.1",
              "assets": {
                "arm64-v8a": "https://example.com/patch.zip"
              },
              "minecraft": ">= 1.20"
            }
            """.utf8
        )

        let version = try JSONDecoder().decode(ModDBVersion.self, from: data)

        XCTAssertEqual(version.version, "0.0.1")
        XCTAssertEqual(version.assets["arm64-v8a"], "https://example.com/patch.zip")
        XCTAssertEqual(version.extraVersions, [])
    }
}
