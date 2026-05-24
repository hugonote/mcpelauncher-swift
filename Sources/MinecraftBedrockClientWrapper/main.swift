import Darwin
import Foundation

private let executableEnvironmentKey = "MCPELAUNCHER_CLIENT_EXECUTABLE"
private let workingDirectoryEnvironmentKey = "MCPELAUNCHER_CLIENT_WORKING_DIRECTORY"
private let outputLogEnvironmentKey = "MCPELAUNCHER_CLIENT_OUTPUT_LOG"

private func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("mcpelauncher-client-wrapper: \(message)\n".utf8))
    exit(status)
}

private func defaultRuntimeURL() -> URL {
    Bundle.main.bundleURL.deletingLastPathComponent()
}

let environment = ProcessInfo.processInfo.environment
let runtimeURL = defaultRuntimeURL()
let executablePath = environment[executableEnvironmentKey]
    ?? runtimeURL.appendingPathComponent("bin/mcpelauncher-client", isDirectory: false).path
let workingDirectoryPath = environment[workingDirectoryEnvironmentKey] ?? runtimeURL.path

guard FileManager.default.isExecutableFile(atPath: executablePath) else {
    fail("client executable is not available at \(executablePath)", status: 66)
}
guard FileManager.default.changeCurrentDirectoryPath(workingDirectoryPath) else {
    fail("could not change directory to \(workingDirectoryPath)", status: 72)
}

if let outputLogPath = environment[outputLogEnvironmentKey], !outputLogPath.isEmpty {
    let descriptor = open(outputLogPath, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    guard descriptor >= 0 else {
        fail("could not open output log at \(outputLogPath): \(String(cString: strerror(errno)))", status: 73)
    }
    dup2(descriptor, STDOUT_FILENO)
    dup2(descriptor, STDERR_FILENO)
    close(descriptor)
}

unsetenv(executableEnvironmentKey)
unsetenv(workingDirectoryEnvironmentKey)
unsetenv(outputLogEnvironmentKey)

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

fail(String(cString: strerror(errno)), status: 127)
