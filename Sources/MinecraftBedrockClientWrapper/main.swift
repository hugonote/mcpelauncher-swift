import Darwin
import Dispatch
import Foundation

private let executableEnvironmentKey = "MCPELAUNCHER_CLIENT_EXECUTABLE"
private let workingDirectoryEnvironmentKey = "MCPELAUNCHER_CLIENT_WORKING_DIRECTORY"
private let outputLogEnvironmentKey = "MCPELAUNCHER_CLIENT_OUTPUT_LOG"
private let googleCredentialFileEnvironmentKey = "MCPELAUNCHER_GOOGLE_CREDENTIAL_FILE"

private final class ChildProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process?) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
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

let environment = ProcessInfo.processInfo.environment
let runtimeURL = defaultRuntimeURL()
let executablePath = environment[executableEnvironmentKey]
    ?? runtimeURL.appendingPathComponent("bin/mcpelauncher-client", isDirectory: false).path
let workingDirectoryPath = environment[workingDirectoryEnvironmentKey] ?? runtimeURL.path
let credentialFilePath = environment[googleCredentialFileEnvironmentKey]

let finish: (Int32) -> Never = { status in
    removeCredentialFile(at: credentialFilePath)
    exit(status)
}
let failWithCleanup: (String, Int32) -> Never = { message, status in
    FileHandle.standardError.write(Data("mcpelauncher-client-wrapper: \(message)\n".utf8))
    finish(status)
}

guard FileManager.default.isExecutableFile(atPath: executablePath) else {
    failWithCleanup("client executable is not available at \(executablePath)", 66)
}
guard FileManager.default.changeCurrentDirectoryPath(workingDirectoryPath) else {
    failWithCleanup("could not change directory to \(workingDirectoryPath)", 72)
}

if let outputLogPath = environment[outputLogEnvironmentKey], !outputLogPath.isEmpty {
    let descriptor = open(outputLogPath, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    guard descriptor >= 0 else {
        failWithCleanup("could not open output log at \(outputLogPath): \(String(cString: strerror(errno)))", 73)
    }
    dup2(descriptor, STDOUT_FILENO)
    dup2(descriptor, STDERR_FILENO)
    close(descriptor)
}

var childEnvironment = environment
childEnvironment.removeValue(forKey: executableEnvironmentKey)
childEnvironment.removeValue(forKey: workingDirectoryEnvironmentKey)
childEnvironment.removeValue(forKey: outputLogEnvironmentKey)

private let childProcess = ChildProcessBox()
private var signalSources: [DispatchSourceSignal] = []

let process = Process()
process.executableURL = URL(fileURLWithPath: executablePath, isDirectory: false)
process.arguments = Array(CommandLine.arguments.dropFirst())
process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath, isDirectory: true)
process.environment = childEnvironment
process.standardInput = FileHandle.nullDevice
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError

do {
    try process.run()
} catch {
    failWithCleanup(error.localizedDescription, 127)
}
childProcess.set(process)
for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
    source.setEventHandler {
        childProcess.terminate()
    }
    source.resume()
    signalSources.append(source)
}
process.waitUntilExit()
childProcess.set(nil)

switch process.terminationReason {
case .exit:
    finish(process.terminationStatus)
case .uncaughtSignal:
    let status = 128 + process.terminationStatus
    if status > Int32(UInt8.max) {
        finish(128)
    }
    finish(status)
@unknown default:
    finish(process.terminationStatus)
}
