import Foundation

public struct ZipArchiveExtractor: @unchecked Sendable {
    private let processRunner: ProcessRunning

    public init(processRunner: ProcessRunning = FoundationProcessRunner()) {
        self.processRunner = processRunner
    }

    public func extract(_ archiveURL: URL, to destinationURL: URL) throws {
        let result = try processRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archiveURL.path, destinationURL.path],
            input: nil,
            currentDirectoryURL: nil,
            environment: [:]
        )
        guard result.status == 0 else {
            throw LauncherError.runtimeInstallFailed(result.stderrString)
        }
    }
}
