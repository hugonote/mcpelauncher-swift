import Darwin
import Foundation
@testable import MinecraftBedrockClientWrapperSupport
import XCTest

final class ProcessGroupIsolationTests: XCTestCase {
    func testNormalWrapperLaunchIsolatesExecedRuntimeProcessGroup() throws {
        let wrapperURL = Bundle(for: ProcessGroupIsolationTests.self)
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("mcpelauncher-client-wrapper", isDirectory: false)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: wrapperURL.path))

        let runtimeExecutableURL = URL(fileURLWithPath: "/bin/sleep", isDirectory: false)
        let inheritedProcessGroupID = getpgrp()
        let runtimeProcessID = try spawn(
            executableURL: wrapperURL,
            arguments: ["30"],
            environment: [
                "MCPELAUNCHER_CLIENT_EXECUTABLE": runtimeExecutableURL.path,
                "MCPELAUNCHER_CLIENT_WORKING_DIRECTORY": "/tmp"
            ]
        )
        defer {
            terminateProcessTreeAndWait(runtimeProcessID)
        }

        let deadline = Date().addingTimeInterval(2)
        while executablePath(for: runtimeProcessID) != runtimeExecutableURL.path,
              processExists(runtimeProcessID),
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        XCTAssertEqual(executablePath(for: runtimeProcessID), runtimeExecutableURL.path)
        XCTAssertNotEqual(runtimeProcessID, inheritedProcessGroupID)
        XCTAssertEqual(getpgid(runtimeProcessID), runtimeProcessID)
    }

    func testSupervisorTerminatesForkedRuntimeChildWhenExecutablePathIsSymlink() throws {
        let wrapperURL = Bundle(for: ProcessGroupIsolationTests.self)
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("mcpelauncher-client-wrapper", isDirectory: false)
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }

        let resolvedRuntimeExecutableURL = URL(fileURLWithPath: "/bin/bash", isDirectory: false)
        let runtimeExecutableURL = temporaryDirectoryURL
            .appendingPathComponent("runtime", isDirectory: false)
        try FileManager.default.createSymbolicLink(
            at: runtimeExecutableURL,
            withDestinationURL: resolvedRuntimeExecutableURL
        )
        let runtimeProcessID = try spawn(
            executableURL: wrapperURL,
            arguments: [
                "-c",
                "/bin/bash -c 'while :; do :; done' & while :; do /bin/sleep 1; done"
            ],
            environment: [
                "MCPELAUNCHER_CLIENT_EXECUTABLE": runtimeExecutableURL.path,
                "MCPELAUNCHER_CLIENT_WORKING_DIRECTORY": "/tmp"
            ]
        )
        defer {
            terminateProcessTreeAndWait(runtimeProcessID)
        }

        let childDiscoveryDeadline = Date().addingTimeInterval(2)
        var forkedRuntimeCandidate: pid_t?
        while forkedRuntimeCandidate == nil, Date() < childDiscoveryDeadline {
            let children = childProcessIdentifiers(of: runtimeProcessID)
            forkedRuntimeCandidate = children.first {
                executablePath(for: $0) == resolvedRuntimeExecutableURL.path
            }
            if forkedRuntimeCandidate == nil {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        let forkedRuntimeProcessID = try XCTUnwrap(forkedRuntimeCandidate)
        let childTerminationDeadline = Date().addingTimeInterval(6)
        while executablePath(for: forkedRuntimeProcessID) != nil,
              Date() < childTerminationDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        XCTAssertNil(executablePath(for: forkedRuntimeProcessID))
        XCTAssertTrue(processExists(runtimeProcessID))
        XCTAssertEqual(executablePath(for: runtimeProcessID), resolvedRuntimeExecutableURL.path)
        XCTAssertEqual(getpgid(runtimeProcessID), runtimeProcessID)
    }

    private func spawn(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> pid_t {
        var processID: pid_t = 0
        var cArguments = ([executableURL.path] + arguments).map { strdup($0) }
        cArguments.append(nil)
        defer {
            cArguments.forEach { free($0) }
        }

        var cEnvironment = environment
            .sorted { $0.key < $1.key }
            .map { strdup("\($0.key)=\($0.value)") }
        cEnvironment.append(nil)
        defer {
            cEnvironment.forEach { free($0) }
        }

        let result = executableURL.path.withCString { executablePath in
            cArguments.withUnsafeMutableBufferPointer { argumentBuffer in
                cEnvironment.withUnsafeMutableBufferPointer { environmentBuffer in
                    posix_spawn(
                        &processID,
                        executablePath,
                        nil,
                        nil,
                        argumentBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result))
        }
        return processID
    }

    private func executablePath(for processID: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(processID, &path, UInt32(path.count)) > 0 else {
            return nil
        }
        return String(
            decoding: path.map { UInt8(bitPattern: $0) }.prefix { $0 != 0 },
            as: UTF8.self
        )
    }

    private func processExists(_ processID: pid_t) -> Bool {
        kill(processID, 0) == 0 || errno == EPERM
    }

    private func childProcessIdentifiers(of processID: pid_t) -> [pid_t] {
        var processIDs = [pid_t](repeating: 0, count: 8)
        let byteCount = processIDs.withUnsafeMutableBytes { buffer in
            proc_listpids(
                UInt32(PROC_PPID_ONLY),
                UInt32(processID),
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard byteCount > 0 else {
            return []
        }
        return processIDs.prefix(Int(byteCount) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }
    }

    private func terminateProcessTreeAndWait(_ processID: pid_t) {
        for childProcessID in childProcessIdentifiers(of: processID) {
            _ = kill(childProcessID, SIGKILL)
        }
        _ = kill(processID, SIGKILL)

        var status: Int32 = 0
        while waitpid(processID, &status, 0) < 0 && errno == EINTR {}
    }
}
