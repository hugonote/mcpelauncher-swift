import Darwin
import Foundation
import MinecraftBedrockClientWrapperSupport

private let superviseArgument = "--supervise-runtime"
private let filterOutputArgument = "--filter-output"
private let executableEnvironmentKey = "MCPELAUNCHER_CLIENT_EXECUTABLE"
private let workingDirectoryEnvironmentKey = "MCPELAUNCHER_CLIENT_WORKING_DIRECTORY"
private let outputLogEnvironmentKey = "MCPELAUNCHER_CLIENT_OUTPUT_LOG"
private let googleCredentialFileEnvironmentKey = "MCPELAUNCHER_GOOGLE_CREDENTIAL_FILE"

private func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("mcpelauncher-client-wrapper: \(message)\n".utf8))
    exit(status)
}

private func defaultRuntimeURL() -> URL {
    Bundle.main.bundleURL.deletingLastPathComponent()
}

private func removeCredentialFile(at path: String?) {
    guard let path, !path.isEmpty else {
        return
    }
    let directoryURL = URL(fileURLWithPath: path, isDirectory: false).deletingLastPathComponent()
    try? FileManager.default.removeItem(at: directoryURL)
}

private func runRuntimeSupervisor(arguments: [String]) -> Never {
    guard arguments.count == 5,
          let pid = pid_t(arguments[1]) else {
        exit(64)
    }
    guard let processGroupID = pid_t(arguments[2]) else {
        exit(64)
    }

    guard ProcessGroupIsolation.isolateCurrentProcess() else {
        exit(71)
    }
    RuntimeProcessGroupSupervisor().supervise(
        runtimeProcessID: pid,
        runtimeProcessGroupID: processGroupID,
        runtimeExecutablePath: arguments[3],
        onRuntimeExit: {
            removeCredentialFile(at: arguments[4])
        }
    )
    exit(0)
}

private func wrapperExecutableURL() -> URL {
    if let executableURL = Bundle.main.executableURL {
        return executableURL
    }
    return URL(fileURLWithPath: CommandLine.arguments[0], isDirectory: false)
}

private func startRuntimeSupervisor(
    runtimeProcessID: pid_t,
    runtimeProcessGroupID: pid_t,
    runtimeExecutablePath: String,
    credentialFilePath: String?
) throws {
    let process = Process()
    process.executableURL = wrapperExecutableURL()
    process.arguments = [
        superviseArgument,
        String(runtimeProcessID),
        String(runtimeProcessGroupID),
        runtimeExecutablePath,
        credentialFilePath ?? ""
    ]
    process.environment = [:]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
}

private func isNoisyImageDecodeLine(_ line: String) -> Bool {
    line.contains("NO LOG FILE! - Image failed to load from memory")
        && line.contains("Reason: unknown image type")
}

private func shouldWriteLogLine(_ line: Data) -> Bool {
    guard let text = String(data: line, encoding: .utf8) else {
        return true
    }
    return !isNoisyImageDecodeLine(text)
}

private func streamFilteredOutput(from input: FileHandle, to output: FileHandle) {
    var pending = Data()
    while true {
        let chunk = input.availableData
        if chunk.isEmpty {
            break
        }
        pending.append(chunk)
        while let newlineIndex = pending.firstIndex(of: 0x0a) {
            let lineEnd = pending.index(after: newlineIndex)
            let line = Data(pending[..<lineEnd])
            if shouldWriteLogLine(line) {
                output.write(line)
            }
            pending.removeSubrange(..<lineEnd)
        }
    }
    if !pending.isEmpty, shouldWriteLogLine(pending) {
        output.write(pending)
    }
}

private func runOutputFilterHelper(arguments: [String]) -> Never {
    guard arguments.count == 2 else {
        exit(64)
    }

    let outputLogPath = arguments[1]
    let descriptor = open(outputLogPath, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    guard descriptor >= 0 else {
        fail("could not open output log at \(outputLogPath): \(String(cString: strerror(errno)))", status: 73)
    }
    let outputHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    streamFilteredOutput(from: .standardInput, to: outputHandle)
    try? outputHandle.close()
    exit(0)
}

private func startOutputFilterHelper(outputLogPath: String) throws -> Int32 {
    var descriptors = (Int32(0), Int32(0))
    let pipeStatus = withUnsafeMutablePointer(to: &descriptors) { pointer in
        pointer.withMemoryRebound(to: Int32.self, capacity: 2) { reboundPointer in
            pipe(reboundPointer)
        }
    }
    guard pipeStatus == 0 else {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: "could not create output filter pipe: \(String(cString: strerror(errno)))"]
        )
    }

    let readDescriptor = descriptors.0
    let writeDescriptor = descriptors.1
    let inputHandle = FileHandle(fileDescriptor: readDescriptor, closeOnDealloc: true)
    let process = Process()
    process.executableURL = wrapperExecutableURL()
    process.arguments = [filterOutputArgument, outputLogPath]
    process.environment = [:]
    process.standardInput = inputHandle
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        try? inputHandle.close()
        return writeDescriptor
    } catch {
        try? inputHandle.close()
        close(writeDescriptor)
        throw error
    }
}

private func redirectOutputToFilter(outputLogPath: String) throws {
    let writeDescriptor = try startOutputFilterHelper(outputLogPath: outputLogPath)
    guard dup2(writeDescriptor, STDOUT_FILENO) >= 0 else {
        close(writeDescriptor)
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: "could not redirect stdout to output filter: \(String(cString: strerror(errno)))"]
        )
    }
    guard dup2(writeDescriptor, STDERR_FILENO) >= 0 else {
        close(writeDescriptor)
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: "could not redirect stderr to output filter: \(String(cString: strerror(errno)))"]
        )
    }
    close(writeDescriptor)
}

let wrapperArguments = Array(CommandLine.arguments.dropFirst())
if wrapperArguments.first == superviseArgument {
    runRuntimeSupervisor(arguments: wrapperArguments)
}
if wrapperArguments.first == filterOutputArgument {
    runOutputFilterHelper(arguments: wrapperArguments)
}

let environment = ProcessInfo.processInfo.environment
let runtimeURL = defaultRuntimeURL()
let executablePath = environment[executableEnvironmentKey]
    ?? runtimeURL.appendingPathComponent("bin/mcpelauncher-client", isDirectory: false).path
let workingDirectoryPath = environment[workingDirectoryEnvironmentKey] ?? runtimeURL.path
let credentialFilePath = environment[googleCredentialFileEnvironmentKey]

let failWithCleanup: (String, Int32) -> Never = { message, status in
    removeCredentialFile(at: credentialFilePath)
    fail(message, status: status)
}

guard FileManager.default.isExecutableFile(atPath: executablePath) else {
    failWithCleanup("client executable is not available at \(executablePath)", 66)
}
guard FileManager.default.changeCurrentDirectoryPath(workingDirectoryPath) else {
    failWithCleanup("could not change directory to \(workingDirectoryPath)", 72)
}
guard ProcessGroupIsolation.isolateCurrentProcess() else {
    failWithCleanup("could not isolate runtime process group", 71)
}

do {
    try startRuntimeSupervisor(
        runtimeProcessID: getpid(),
        runtimeProcessGroupID: getpgrp(),
        runtimeExecutablePath: executablePath,
        credentialFilePath: credentialFilePath
    )
} catch {
    failWithCleanup("could not start runtime supervisor: \(error.localizedDescription)", 74)
}

unsetenv(executableEnvironmentKey)
unsetenv(workingDirectoryEnvironmentKey)
unsetenv(outputLogEnvironmentKey)

if let outputLogPath = environment[outputLogEnvironmentKey], !outputLogPath.isEmpty {
    do {
        try redirectOutputToFilter(outputLogPath: outputLogPath)
    } catch {
        failWithCleanup(error.localizedDescription, 73)
    }
}

var arguments = [executablePath]
arguments.append(contentsOf: CommandLine.arguments.dropFirst())
var cArguments = arguments.map { strdup($0) }
cArguments.append(nil)
defer {
    for pointer in cArguments {
        free(pointer)
    }
}

_ = cArguments.withUnsafeMutableBufferPointer { buffer in
    execv(executablePath, buffer.baseAddress)
}

failWithCleanup(String(cString: strerror(errno)), 127)
