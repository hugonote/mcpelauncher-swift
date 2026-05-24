import Foundation
@testable import MinecraftBedrockLauncherCore

final class TemporaryDirectory {
    let url: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.url = fileManager.temporaryDirectory
            .appendingPathComponent("SwiftLauncherTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? fileManager.removeItem(at: url)
    }
}

struct MockProcessRunner: ProcessRunning, @unchecked Sendable {
    var handler: @Sendable (URL, [String], Data?, URL?, [String: String]) throws -> ProcessResult

    func run(
        executableURL: URL,
        arguments: [String],
        input: Data?,
        currentDirectoryURL: URL?,
        environment: [String: String]
    ) throws -> ProcessResult {
        try handler(executableURL, arguments, input, currentDirectoryURL, environment)
    }
}

final class MockRuntimeApplicationLauncher: RuntimeApplicationLaunching, @unchecked Sendable {
    struct Launch {
        var appURL: URL
        var arguments: [String]
        var environment: [String: String]
    }

    var launches: [Launch] = []
    var error: Error?

    func launchApplication(at appURL: URL, arguments: [String], environment: [String: String]) throws {
        if let error {
            throw error
        }
        launches.append(Launch(appURL: appURL, arguments: arguments, environment: environment))
    }
}

func writeExecutable(_ url: URL, contents: String = "#!/bin/zsh\nexit 0\n") throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
