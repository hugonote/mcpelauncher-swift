import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var status: Int32
    public var stdout: Data
    public var stderr: Data

    public init(status: Int32, stdout: Data, stderr: Data) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    public var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

public protocol ProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        input: Data?,
        currentDirectoryURL: URL?,
        environment: [String: String]
    ) throws -> ProcessResult
}

public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        input: Data? = nil,
        currentDirectoryURL: URL? = nil,
        environment: [String: String] = [:]
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        var mergedEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            if value.isEmpty {
                mergedEnvironment.removeValue(forKey: key)
            } else {
                mergedEnvironment[key] = value
            }
        }
        process.environment = mergedEnvironment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdin: Pipe?
        if input != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdin = pipe
        } else {
            stdin = nil
        }

        try process.run()

        if let input, let stdin {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(status: process.terminationStatus, stdout: outData, stderr: errData)
    }
}
