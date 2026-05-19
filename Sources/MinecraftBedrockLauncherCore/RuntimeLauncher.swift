import Darwin
import Foundation

public enum RuntimeWarmUpResult: Equatable, Sendable {
    case loadedPairIP
    case acceptedFirstRunPairIPCrash
}

public struct RuntimeLauncher: @unchecked Sendable {
    private let fileManager: FileManager
    private let processRunner: ProcessRunning

    public init(
        fileManager: FileManager = .default,
        processRunner: ProcessRunning = FoundationProcessRunner()
    ) {
        self.fileManager = fileManager
        self.processRunner = processRunner
    }

    public func launch(
        runtimePath: URL,
        version: InstalledVersion,
        compatibilityPatchPath: URL? = nil,
        dataPath: URL? = nil,
        cachePath: URL? = nil,
        credentialsHelperDirectory: URL? = nil,
        googleCredential: GoogleCredential? = nil,
        logURL: URL? = nil
    ) throws {
        let executableURL = try runtimeExecutable(in: runtimePath)
        var arguments = ["--disable-fmod"]
        if !Self.falseyEnvironmentValue("MCPELAUNCHER_FORCE_FES") {
            arguments.append("-fes")
        }
        if let compatibilityPatchPath {
            arguments += ["-m", compatibilityPatchPath.path]
        }
        if let dataPath {
            arguments += ["-dd", dataPath.path]
        }
        if let cachePath {
            arguments += ["-dc", cachePath.path]
        }
        arguments += ["-dg", version.installPath.path]

        let currentDirectoryURL = runtimeWorkingDirectory(for: executableURL, runtimePath: runtimePath)

        var environment = [
            "SDL_AUDIODRIVER": ProcessInfo.processInfo.environment["SDL_AUDIODRIVER"] ?? "coreaudio",
            "AUDIO_SAMPLE_RATE": ProcessInfo.processInfo.environment["AUDIO_SAMPLE_RATE"] ?? "48000"
        ]
        let xdgRuntimeDataURL = runtimePath.appendingPathComponent("Resources/mcpelauncher", isDirectory: true)
        if fileManager.fileExists(atPath: xdgRuntimeDataURL.path) {
            var xdgDataDirs = runtimePath.appendingPathComponent("Resources", isDirectory: true).path
            if let existing = ProcessInfo.processInfo.environment["XDG_DATA_DIRS"], !existing.isEmpty {
                xdgDataDirs += ":\(existing)"
            }
            environment["XDG_DATA_DIRS"] = xdgDataDirs
        }
        if let credentialsHelperDirectory {
            let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = credentialsHelperDirectory.path + ":" + existingPath
        }
        if let googleCredential {
            environment["MCPELAUNCHER_GOOGLE_EMAIL"] = googleCredential.email
            environment["MCPELAUNCHER_GOOGLE_TOKEN"] = googleCredential.masterToken
        }

        let result = try processRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            input: nil,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment
        )
        try writeLaunchLog(
            result,
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            logURL: logURL
        )
        guard result.status == 0 else {
            throw LauncherError.gameLaunchFailed(
                status: result.status,
                logURL: logURL,
                outputTail: Self.outputTail(stdout: result.stdoutString, stderr: result.stderrString)
            )
        }
    }

    public func launchDetached(
        runtimePath: URL,
        version: InstalledVersion,
        compatibilityPatchPath: URL? = nil,
        dataPath: URL? = nil,
        cachePath: URL? = nil,
        credentialsHelperDirectory: URL? = nil,
        googleCredential: GoogleCredential? = nil,
        logURL: URL? = nil
    ) throws {
        let command = try launchCommand(
            runtimePath: runtimePath,
            version: version,
            compatibilityPatchPath: compatibilityPatchPath,
            dataPath: dataPath,
            cachePath: cachePath,
            credentialsHelperDirectory: credentialsHelperDirectory,
            googleCredential: googleCredential
        )

        let outputHandle = try writeDetachedLaunchLog(command, logURL: logURL)

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.currentDirectoryURL
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle ?? FileHandle.nullDevice
        process.standardError = outputHandle ?? FileHandle.nullDevice
        try process.run()
    }

    public func warmUpFirstLaunch(
        runtimePath: URL,
        version: InstalledVersion,
        compatibilityPatchPath: URL,
        dataPath: URL,
        cachePath: URL,
        credentialsHelperDirectory: URL,
        googleCredential: GoogleCredential? = nil,
        logURL: URL? = nil,
        timeout: TimeInterval = 45
    ) throws -> RuntimeWarmUpResult {
        var command = try launchCommand(
            runtimePath: runtimePath,
            version: version,
            compatibilityPatchPath: compatibilityPatchPath,
            dataPath: dataPath,
            cachePath: cachePath,
            credentialsHelperDirectory: credentialsHelperDirectory,
            googleCredential: googleCredential
        )
        command.arguments += ["-ww", "1", "-wh", "1"]

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.currentDirectoryURL
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        let outputTail = RuntimeWarmUpOutputTail(limit: 512 * 1024)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let shouldContinue = autoreleasepool {
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty {
                        return false
                    }
                    outputTail.append(chunk)
                    return true
                }
                if !shouldContinue {
                    break
                }
            }
            group.leave()
        }

        try process.run()
        ChildProcessRegistry.shared.register(process)
        defer {
            if process.isRunning {
                process.terminate()
                kill(process.processIdentifier, SIGKILL)
            }
            ChildProcessRegistry.shared.unregister(process)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            let text = outputTail.text()
            if Self.didLoadPairIP(text) {
                process.terminate()
                break
            }
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        process.waitUntilExit()
        group.wait()

        let text = outputTail.text()
        try writeWarmUpLaunchLog(
            command: command,
            status: process.terminationStatus,
            output: text,
            logURL: logURL
        )

        if Self.didLoadPairIP(text) {
            return .loadedPairIP
        }
        if Self.isExpectedFirstRunPairIPCrash(
            status: process.terminationStatus,
            output: text,
            dataPath: dataPath,
            fileManager: fileManager
        ) {
            return .acceptedFirstRunPairIPCrash
        }

        let status = timedOut ? SIGTERM : process.terminationStatus
        throw LauncherError.gameLaunchFailed(
            status: status,
            logURL: logURL,
            outputTail: Self.outputTail(stdout: text, stderr: "")
        )
    }

    public func runtimeExecutable(in runtimePath: URL) throws -> URL {
        let candidates = [
            runtimePath.appendingPathComponent("bin/mcpelauncher-client"),
            runtimePath.appendingPathComponent("MacOS/mcpelauncher-client-arm64-v8a"),
            runtimePath.appendingPathComponent("Contents/MacOS/mcpelauncher-client-arm64-v8a"),
            runtimePath.appendingPathComponent("MacOS/mcpelauncher-client"),
            runtimePath.appendingPathComponent("Contents/MacOS/mcpelauncher-client"),
            runtimePath.appendingPathComponent("Resources/Minecraft Bedrock/mcpelauncher-client/mcpelauncher-client"),
            runtimePath.appendingPathComponent("Resources/Minecraft Bedrock/mcpelauncher-client/mcpelauncher-client-arm64-v8a"),
            runtimePath.appendingPathComponent("mcpelauncher-client/mcpelauncher-client"),
            runtimePath.appendingPathComponent("mcpelauncher-client")
        ]
        if let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return executable
        }
        throw LauncherError.missingRuntimeExecutable(runtimePath)
    }

    func runtimeWorkingDirectory(for executableURL: URL, runtimePath: URL) -> URL {
        let appRuntimeRoot = runtimePath.appendingPathComponent("Resources/Minecraft Bedrock", isDirectory: true)
        if executableURL.path.hasPrefix(appRuntimeRoot.path + "/") {
            return appRuntimeRoot
        }
        if executableURL.deletingLastPathComponent().lastPathComponent == "bin" {
            return runtimePath
        }
        if executableURL.deletingLastPathComponent().lastPathComponent == "mcpelauncher-client" {
            return executableURL.deletingLastPathComponent().deletingLastPathComponent()
        }
        return executableURL.deletingLastPathComponent()
    }

    private func launchCommand(
        runtimePath: URL,
        version: InstalledVersion,
        compatibilityPatchPath: URL?,
        dataPath: URL?,
        cachePath: URL?,
        credentialsHelperDirectory: URL?,
        googleCredential: GoogleCredential?
    ) throws -> LaunchCommand {
        let executableURL = try runtimeExecutable(in: runtimePath)
        var arguments = ["--disable-fmod"]
        if !Self.falseyEnvironmentValue("MCPELAUNCHER_FORCE_FES") {
            arguments.append("-fes")
        }
        if let compatibilityPatchPath {
            arguments += ["-m", compatibilityPatchPath.path]
        }
        if let dataPath {
            arguments += ["-dd", dataPath.path]
        }
        if let cachePath {
            arguments += ["-dc", cachePath.path]
        }
        arguments += ["-dg", version.installPath.path]

        let currentDirectoryURL = runtimeWorkingDirectory(for: executableURL, runtimePath: runtimePath)

        var environment = ProcessInfo.processInfo.environment
        environment["SDL_AUDIODRIVER"] = ProcessInfo.processInfo.environment["SDL_AUDIODRIVER"] ?? "coreaudio"
        environment["AUDIO_SAMPLE_RATE"] = ProcessInfo.processInfo.environment["AUDIO_SAMPLE_RATE"] ?? "48000"

        let xdgRuntimeDataURL = runtimePath.appendingPathComponent("Resources/mcpelauncher", isDirectory: true)
        if fileManager.fileExists(atPath: xdgRuntimeDataURL.path) {
            var xdgDataDirs = runtimePath.appendingPathComponent("Resources", isDirectory: true).path
            if let existing = ProcessInfo.processInfo.environment["XDG_DATA_DIRS"], !existing.isEmpty {
                xdgDataDirs += ":\(existing)"
            }
            environment["XDG_DATA_DIRS"] = xdgDataDirs
        }
        if let credentialsHelperDirectory {
            let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = credentialsHelperDirectory.path + ":" + existingPath
        }
        if let googleCredential {
            environment["MCPELAUNCHER_GOOGLE_EMAIL"] = googleCredential.email
            environment["MCPELAUNCHER_GOOGLE_TOKEN"] = googleCredential.masterToken
        }

        return LaunchCommand(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment
        )
    }

    private static func falseyEnvironmentValue(_ name: String) -> Bool {
        guard let value = ProcessInfo.processInfo.environment[name]?.lowercased() else {
            return false
        }
        return value == "0" || value == "false" || value == "no"
    }

    private func writeLaunchLog(
        _ result: ProcessResult,
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String],
        logURL: URL?
    ) throws {
        guard let logURL else {
            return
        }
        let environmentText = environment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        let text = """
        executable: \(executableURL.path)
        arguments: \(arguments.joined(separator: " "))
        cwd: \(currentDirectoryURL.path)
        status: \(result.status)

        environment:
        \(environmentText)

        stdout:
        \(result.stdoutString)

        stderr:
        \(result.stderrString)
        """
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func writeDetachedLaunchLog(_ command: LaunchCommand, logURL: URL?) throws -> FileHandle? {
        guard let logURL else {
            return nil
        }
        let text = """
        executable: \(command.executableURL.path)
        arguments: \(command.arguments.joined(separator: " "))
        cwd: \(command.currentDirectoryURL.path)
        status: detached

        stdout/stderr:

        """
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: logURL, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        return handle
    }

    private func writeWarmUpLaunchLog(
        command: LaunchCommand,
        status: Int32,
        output: String,
        logURL: URL?
    ) throws {
        guard let logURL else {
            return
        }
        let text = """
        executable: \(command.executableURL.path)
        arguments: \(command.arguments.joined(separator: " "))
        cwd: \(command.currentDirectoryURL.path)
        status: warmup \(status)

        stdout/stderr:
        \(output)
        """
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func didLoadPairIP(_ output: String) -> Bool {
        output.contains("Loaded libpairipcore")
    }

    private static func isExpectedFirstRunPairIPCrash(
        status: Int32,
        output: String,
        dataPath: URL,
        fileManager: FileManager
    ) -> Bool {
        guard status != 0,
              output.contains("Signal 11 received"),
              output.contains("libpairipcore.so"),
              output.contains("Starting download") else {
            return false
        }
        return fileManager.fileExists(
            atPath: dataPath.appendingPathComponent("pass.token", isDirectory: false).path
        )
    }

    private static func outputTail(stdout: String, stderr: String) -> String {
        let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        guard output.count > 4_000 else {
            return output
        }
        return String(output.suffix(4_000))
    }
}

private struct LaunchCommand {
    var executableURL: URL
    var arguments: [String]
    var currentDirectoryURL: URL
    var environment: [String: String]
}

private final class RuntimeWarmUpOutputTail: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        if data.count > limit {
            data = Data(data.suffix(limit))
        }
        lock.unlock()
    }

    func text() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}
