import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class LauncherInstanceCoordinatorTests: XCTestCase {
    private static let helperPortNameKey = "MBL_TEST_INSTANCE_PORT_NAME"
    private static let helperReadyPathKey = "MBL_TEST_INSTANCE_READY_PATH"
    private static let helperExpectedPathKey = "MBL_TEST_INSTANCE_EXPECTED_PATH"

    func testSecondaryForwardsURLsAcrossProcesses() async throws {
        let environment = ProcessInfo.processInfo.environment
        if let helperPortName = environment[Self.helperPortNameKey] {
            try await runPrimaryHelper(
                portName: helperPortName,
                readyPath: try XCTUnwrap(environment[Self.helperReadyPathKey]),
                expectedPath: try XCTUnwrap(environment[Self.helperExpectedPathKey])
            )
            return
        }

        let temporaryDirectory = try TemporaryDirectory()
        let readyURL = temporaryDirectory.url.appendingPathComponent("primary-ready")
        let expectedURL = temporaryDirectory.url.appendingPathComponent("Forwarded.mcworld")
        let portName = portName()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let primaryProcess = Process()
        primaryProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        primaryProcess.arguments = [
            "xctest",
            "-XCTest",
            "LauncherInstanceCoordinatorTests/testSecondaryForwardsURLsAcrossProcesses",
            Bundle(for: LauncherInstanceCoordinatorTests.self).bundlePath
        ]
        primaryProcess.standardOutput = outputPipe
        primaryProcess.standardError = errorPipe
        var helperEnvironment = environment
        helperEnvironment[Self.helperPortNameKey] = portName
        helperEnvironment[Self.helperReadyPathKey] = readyURL.path
        helperEnvironment[Self.helperExpectedPathKey] = expectedURL.path
        primaryProcess.environment = helperEnvironment

        try primaryProcess.run()
        defer {
            if primaryProcess.isRunning {
                primaryProcess.terminate()
            }
        }

        let primaryBecameReady = await waitUntil {
            FileManager.default.fileExists(atPath: readyURL.path) || !primaryProcess.isRunning
        }
        guard primaryBecameReady,
              FileManager.default.fileExists(atPath: readyURL.path) else {
            if primaryProcess.isRunning {
                primaryProcess.terminate()
                primaryProcess.waitUntilExit()
            }
            XCTFail("Primary helper did not start.\n\(processOutput(outputPipe, errorPipe))")
            return
        }

        let secondary = LauncherInstanceCoordinator(portName: portName)
        defer { secondary.shutdown() }
        XCTAssertEqual(secondary.role, .secondary)
        let delivered = await secondary.forward([expectedURL])
        XCTAssertTrue(delivered)

        if !(await waitUntil({ !primaryProcess.isRunning })) {
            primaryProcess.terminate()
        }
        primaryProcess.waitUntilExit()
        XCTAssertEqual(
            primaryProcess.terminationStatus,
            0,
            processOutput(outputPipe, errorPipe)
        )
    }

    func testSecondaryForwardsURLsAndWaitsForPrimaryAcknowledgement() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let portName = portName()
        let primary = LauncherInstanceCoordinator(portName: portName)
        let secondary = LauncherInstanceCoordinator(portName: portName)
        defer {
            secondary.shutdown()
            primary.shutdown()
        }
        XCTAssertEqual(primary.role, .primary)
        XCTAssertEqual(secondary.role, .secondary)

        let expectedURLs = [
            temporaryDirectory.url.appendingPathComponent("World.mcworld"),
            temporaryDirectory.url.appendingPathComponent("Resources.mcpack")
        ]
        let receivedRequest = expectation(description: "Primary received forwarded URLs")
        primary.setRequestHandler { urls in
            XCTAssertEqual(urls, expectedURLs)
            receivedRequest.fulfill()
        }

        let delivered = await secondary.forward(expectedURLs)

        XCTAssertTrue(delivered)
        await fulfillment(of: [receivedRequest], timeout: 1)
    }

    func testRequestIsBufferedUntilPrimaryInstallsHandler() async throws {
        let temporaryDirectory = try TemporaryDirectory()
        let portName = portName()
        let primary = LauncherInstanceCoordinator(portName: portName)
        let secondary = LauncherInstanceCoordinator(portName: portName)
        defer {
            secondary.shutdown()
            primary.shutdown()
        }
        let expectedURL = temporaryDirectory.url.appendingPathComponent("Buffered.mcworld")

        let delivered = await secondary.forward([expectedURL])
        XCTAssertTrue(delivered)

        let receivedRequest = expectation(description: "Buffered request was delivered")
        primary.setRequestHandler { urls in
            XCTAssertEqual(urls, [expectedURL])
            receivedRequest.fulfill()
        }
        await fulfillment(of: [receivedRequest], timeout: 1)
    }

    func testEmptyRequestActivatesPrimary() async throws {
        let portName = portName()
        let primary = LauncherInstanceCoordinator(portName: portName)
        let secondary = LauncherInstanceCoordinator(portName: portName)
        defer {
            secondary.shutdown()
            primary.shutdown()
        }

        let receivedRequest = expectation(description: "Primary received activation request")
        primary.setRequestHandler { urls in
            XCTAssertTrue(urls.isEmpty)
            receivedRequest.fulfill()
        }

        let delivered = await secondary.forward([])
        XCTAssertTrue(delivered)
        await fulfillment(of: [receivedRequest], timeout: 1)
    }

    func testNewPrimaryCanStartAfterPreviousPrimaryShutsDown() throws {
        let portName = portName()
        let firstPrimary = LauncherInstanceCoordinator(portName: portName)
        XCTAssertEqual(firstPrimary.role, .primary)

        firstPrimary.shutdown()

        let replacementPrimary = LauncherInstanceCoordinator(portName: portName)
        defer { replacementPrimary.shutdown() }
        XCTAssertEqual(replacementPrimary.role, .primary)
    }

    private func portName() -> String {
        "local.minecraft.bedrock.swiftlauncher.test.\(UUID().uuidString)"
    }

    private func runPrimaryHelper(
        portName: String,
        readyPath: String,
        expectedPath: String
    ) async throws {
        let primary = LauncherInstanceCoordinator(portName: portName)
        defer { primary.shutdown() }
        guard primary.role == .primary else {
            XCTFail("Primary helper started as \(primary.role).")
            return
        }

        let receivedRequest = expectation(description: "Primary helper received forwarded URL")
        primary.setRequestHandler { urls in
            XCTAssertEqual(urls, [URL(fileURLWithPath: expectedPath)])
            receivedRequest.fulfill()
        }
        try Data([1]).write(to: URL(fileURLWithPath: readyPath), options: .atomic)
        await fulfillment(of: [receivedRequest], timeout: 5)
    }

    private func waitUntil(
        _ condition: @escaping () -> Bool,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func processOutput(_ outputPipe: Pipe, _ errorPipe: Pipe) -> String {
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: output + error, as: UTF8.self)
    }
}
