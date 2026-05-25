import Darwin
import Foundation

private let cleanupArgument = "--cleanup-credential-file"
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

private func waitForProcessExit(pid: pid_t) {
    let queue = kqueue()
    guard queue >= 0 else {
        waitForProcessExitByPolling(pid: pid)
        return
    }
    defer {
        close(queue)
    }

    var event = kevent(
        ident: UInt(pid),
        filter: Int16(EVFILT_PROC),
        flags: UInt16(EV_ADD | EV_ENABLE),
        fflags: UInt32(NOTE_EXIT),
        data: 0,
        udata: nil
    )
    let registration = withUnsafePointer(to: &event) { pointer in
        pointer.withMemoryRebound(to: kevent.self, capacity: 1) { reboundPointer in
            kevent(queue, reboundPointer, 1, nil, 0, nil)
        }
    }
    guard registration == 0 else {
        if errno != ESRCH {
            waitForProcessExitByPolling(pid: pid)
        }
        return
    }

    var exitEvent = kevent()
    _ = withUnsafeMutablePointer(to: &exitEvent) { pointer in
        pointer.withMemoryRebound(to: kevent.self, capacity: 1) { reboundPointer in
            kevent(queue, nil, 0, reboundPointer, 1, nil)
        }
    }
}

private func waitForProcessExitByPolling(pid: pid_t) {
    while kill(pid, 0) == 0 || errno == EPERM {
        sleep(1)
    }
}

private func runCredentialCleanupHelper(arguments: [String]) -> Never {
    guard arguments.count == 3,
          let pid = pid_t(arguments[1]) else {
        exit(64)
    }

    waitForProcessExit(pid: pid)
    removeCredentialFile(at: arguments[2])
    exit(0)
}

private func wrapperExecutableURL() -> URL {
    if let executableURL = Bundle.main.executableURL {
        return executableURL
    }
    return URL(fileURLWithPath: CommandLine.arguments[0], isDirectory: false)
}

private func startCredentialCleanupHelper(for credentialFilePath: String?) throws {
    guard let credentialFilePath, !credentialFilePath.isEmpty else {
        return
    }

    let process = Process()
    process.executableURL = wrapperExecutableURL()
    process.arguments = [
        cleanupArgument,
        String(getpid()),
        credentialFilePath
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
if wrapperArguments.first == cleanupArgument {
    runCredentialCleanupHelper(arguments: wrapperArguments)
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

do {
    try startCredentialCleanupHelper(for: credentialFilePath)
} catch {
    failWithCleanup("could not start credential cleanup helper: \(error.localizedDescription)", 74)
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
