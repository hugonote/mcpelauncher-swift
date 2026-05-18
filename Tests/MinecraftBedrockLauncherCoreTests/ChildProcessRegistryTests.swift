import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class ChildProcessRegistryTests: XCTestCase {
    func testTerminateAllKillsRegisteredProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        ChildProcessRegistry.shared.register(process)

        ChildProcessRegistry.shared.terminateAll()
        process.waitUntilExit()
        ChildProcessRegistry.shared.unregister(process)

        XCTAssertFalse(process.isRunning)
        XCTAssertNotEqual(process.terminationStatus, 0)
    }
}
