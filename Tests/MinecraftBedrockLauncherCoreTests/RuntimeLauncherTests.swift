import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class RuntimeLauncherTests: XCTestCase {
    func testLaunchUsesBundledHelpersWithoutCopyingThemIntoRuntime() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let runtimeBinURL = runtimeURL.appendingPathComponent("MacOS", isDirectory: true)
        let executableURL = runtimeBinURL.appendingPathComponent("mcpelauncher-client")
        let helpersURL = temp.url.appendingPathComponent("Helpers", isDirectory: true)

        try FileManager.default.createDirectory(at: runtimeBinURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helpersURL, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: executableURL.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let runner = RecordingProcessRunner()
        try RuntimeLauncher(processRunner: runner).launch(
            runtimePath: runtimeURL,
            version: InstalledVersion(versionName: "test", versionCode: 1, installPath: temp.url),
            credentialsHelperDirectory: helpersURL
        )

        XCTAssertEqual(runner.environment?["PATH"]?.split(separator: ":").first, Substring(helpersURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: runtimeBinURL.appendingPathComponent("mcpelauncher-webview").path))
    }
}

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    var environment: [String: String]?

    func run(
        executableURL: URL,
        arguments: [String],
        input: Data?,
        currentDirectoryURL: URL?,
        environment: [String: String]
    ) throws -> ProcessResult {
        self.environment = environment
        return ProcessResult(status: 0, stdout: Data(), stderr: Data())
    }
}
