import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class RuntimeLauncherArgumentsTests: XCTestCase {
    func testClientArguments() {
        let game = URL(fileURLWithPath: "/data/game-versions/1.26.10")
        let data = URL(fileURLWithPath: "/data/MinecraftData")
        let patch = URL(fileURLWithPath: "/data/CompatibilityPatches/1.0/arm64-v8a")
        let zoom = URL(fileURLWithPath: "/data/Mods/zoom/1.0/arm64-v8a")
        let fullbright = URL(fileURLWithPath: "/data/Mods/fullbright/2.0/arm64-v8a")

        let cases: [(name: String, mods: [URL], expectedMods: String?)] = [
            ("no mods", [], nil),
            ("patch only", [patch], patch.path),
            ("patch and mods", [patch, zoom, fullbright], "\(patch.path),\(zoom.path),\(fullbright.path)")
        ]
        for testCase in cases {
            let arguments = RuntimeLauncher.clientArguments(
                gamePath: game,
                modDirectories: testCase.mods,
                dataPath: data,
                cachePath: data
            )
            let modArgument = arguments.firstIndex(of: "-m").map { arguments[$0 + 1] }
            XCTAssertEqual(modArgument, testCase.expectedMods, testCase.name)
            XCTAssertEqual(arguments.filter { $0 == "-m" }.count, testCase.expectedMods == nil ? 0 : 1, testCase.name)
            XCTAssertEqual(Array(arguments.suffix(6)), ["-dd", data.path, "-dc", data.path, "-dg", game.path], testCase.name)
        }
    }
}
