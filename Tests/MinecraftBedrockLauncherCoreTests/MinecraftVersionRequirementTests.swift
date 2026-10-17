import XCTest
@testable import MinecraftBedrockLauncherCore

final class MinecraftVersionRequirementTests: XCTestCase {
    func testIsSatisfied() {
        let cases: [(requirement: String, version: String, expected: Bool)] = [
            (">= 1.21.0", "1.21.0", true),
            (">= 1.21.0", "1.26.10", true),
            (">= 1.21.0", "1.20.80", false),
            (">=1.21", "1.21.0.3", true),
            ("> 1.21.0", "1.21.0", false),
            ("< 1.21.0", "1.20.80", true),
            ("<= 1.21.0", "1.21.0", true),
            ("1.21.0", "1.21.0", true),
            ("== 1.21.0", "1.21.1", false),
            (">= 1.21.0", "beta", true)
        ]
        for testCase in cases {
            let requirement = MinecraftVersionRequirement(testCase.requirement)
            XCTAssertEqual(
                requirement?.isSatisfied(by: testCase.version),
                testCase.expected,
                "\(testCase.requirement) vs \(testCase.version)"
            )
        }
    }

    func testRejectsUnparseableRequirement() {
        let cases = ["", ">= ", "latest", ">= 1.x"]
        for testCase in cases {
            XCTAssertNil(MinecraftVersionRequirement(testCase), testCase)
        }
    }
}
