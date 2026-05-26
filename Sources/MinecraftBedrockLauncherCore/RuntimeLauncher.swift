import Darwin
import Foundation

public enum RuntimeWarmUpResult: Equatable, Sendable {
    case loadedPairIP
    case acceptedFirstRunPairIPCrash
}

public struct RuntimeLauncher: @unchecked Sendable {
    private static let clientAppName = "Minecraft Bedrock"
    private static let clientWrapperExecutableName = "mcpelauncher-client-wrapper"
    private static let clientIconName = "minecraft-bedrock"
    public static let clientBundleIdentifier = "local.minecraft.bedrock.swiftlauncher.client"

    private let fileManager: FileManager
    private let processRunner: ProcessRunning
    private let applicationLauncher: any RuntimeApplicationLaunching
    private let detachedCredentialCleanupDelay: TimeInterval

    public init(
        fileManager: FileManager = .default,
        processRunner: ProcessRunning = FoundationProcessRunner(),
        applicationLauncher: any RuntimeApplicationLaunching = NSWorkspaceRuntimeApplicationLauncher(),
        detachedCredentialCleanupDelay: TimeInterval = 120
    ) {
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.applicationLauncher = applicationLauncher
        self.detachedCredentialCleanupDelay = detachedCredentialCleanupDelay
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

        let credentialFileURL = try googleCredential.map {
            try GoogleCredentialFileTransfer.writeCredential($0, fileManager: fileManager)
        }
        defer {
            GoogleCredentialFileTransfer.removeCredentialFile(at: credentialFileURL, fileManager: fileManager)
        }

        var environment = [
            "SDL_AUDIODRIVER": ProcessInfo.processInfo.environment["SDL_AUDIODRIVER"] ?? "coreaudio",
            "AUDIO_SAMPLE_RATE": ProcessInfo.processInfo.environment["AUDIO_SAMPLE_RATE"] ?? "48000",
            "MCPELAUNCHER_GOOGLE_EMAIL": "",
            "MCPELAUNCHER_GOOGLE_TOKEN": "",
            GoogleCredentialFileTransfer.environmentKey: ""
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
        if let credentialFileURL {
            environment[GoogleCredentialFileTransfer.environmentKey] = credentialFileURL.path
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
        logURL: URL? = nil,
        clientWrapperExecutableURL: URL? = nil,
        clientWrapperIconURL: URL? = nil
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

        let capturesProcessOutput = logURL != nil

        if let clientWrapperExecutableURL,
           fileManager.isExecutableFile(atPath: clientWrapperExecutableURL.path) {
            let appURL = try prepareClientAppBundle(
                runtimePath: runtimePath,
                clientWrapperExecutableURL: clientWrapperExecutableURL,
                iconURL: clientWrapperIconURL
            )
            var environment = command.environment
            environment[RuntimeClientWrapperEnvironment.executableKey] = command.executableURL.path
            environment[RuntimeClientWrapperEnvironment.workingDirectoryKey] = command.currentDirectoryURL.path
            if capturesProcessOutput, let logURL {
                environment[RuntimeClientWrapperEnvironment.outputLogKey] = logURL.path
            }

            _ = try writeDetachedLaunchLog(
                command,
                logURL: logURL,
                capturesProcessOutput: capturesProcessOutput,
                appBundleURL: appURL
            )
            do {
                try applicationLauncher.launchApplication(
                    at: appURL,
                    arguments: command.arguments,
                    environment: environment
                )
            } catch {
                GoogleCredentialFileTransfer.removeCredentialFile(at: command.credentialFileURL, fileManager: fileManager)
                throw error
            }
            return
        }

        let outputHandle = try writeDetachedLaunchLog(
            command,
            logURL: logURL,
            capturesProcessOutput: capturesProcessOutput
        )

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.currentDirectoryURL
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle ?? FileHandle.nullDevice
        process.standardError = outputHandle ?? FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            GoogleCredentialFileTransfer.removeCredentialFile(at: command.credentialFileURL, fileManager: fileManager)
            throw error
        }
        scheduleDetachedCredentialCleanup(command.credentialFileURL)
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
        defer {
            GoogleCredentialFileTransfer.removeCredentialFile(at: command.credentialFileURL, fileManager: fileManager)
        }
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

    func runtimeClientAppBundleURL(in runtimePath: URL) -> URL {
        runtimePath.appendingPathComponent("\(Self.clientAppName).app", isDirectory: true)
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
        environment.removeValue(forKey: "MCPELAUNCHER_GOOGLE_EMAIL")
        environment.removeValue(forKey: "MCPELAUNCHER_GOOGLE_TOKEN")
        environment.removeValue(forKey: GoogleCredentialFileTransfer.environmentKey)
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
        let credentialFileURL = try googleCredential.map {
            try GoogleCredentialFileTransfer.writeCredential($0, fileManager: fileManager)
        }
        if let credentialFileURL {
            environment[GoogleCredentialFileTransfer.environmentKey] = credentialFileURL.path
        }

        return LaunchCommand(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            credentialFileURL: credentialFileURL
        )
    }

    private static func falseyEnvironmentValue(_ name: String) -> Bool {
        guard let value = ProcessInfo.processInfo.environment[name]?.lowercased() else {
            return false
        }
        return value == "0" || value == "false" || value == "no"
    }

    private func scheduleDetachedCredentialCleanup(_ credentialFileURL: URL?) {
        GoogleCredentialFileTransfer.scheduleCredentialFileRemoval(
            at: credentialFileURL,
            after: detachedCredentialCleanupDelay,
            fileManager: fileManager
        )
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
            .map { "\($0.key)=\(Self.redactedEnvironmentValue(key: $0.key, value: $0.value))" }
            .joined(separator: "\n")
        let text = """
        executable: \(executableURL.path)
        arguments: \(arguments.joined(separator: " "))
        cwd: \(currentDirectoryURL.path)
        status: \(result.status)

        environment:
        \(environmentText)

        stdout:
        \(Self.redactedText(result.stdoutString))

        stderr:
        \(Self.redactedText(result.stderrString))
        """
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: logURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: logURL.path)
    }

    private func prepareClientAppBundle(
        runtimePath: URL,
        clientWrapperExecutableURL: URL,
        iconURL: URL?
    ) throws -> URL {
        let appURL = runtimeClientAppBundleURL(in: runtimePath)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let wrapperDestinationURL = macOSURL.appendingPathComponent(Self.clientWrapperExecutableName, isDirectory: false)
        try copyItemReplacingExisting(from: clientWrapperExecutableURL, to: wrapperDestinationURL)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: wrapperDestinationURL.path)

        if let iconURL, fileManager.fileExists(atPath: iconURL.path) {
            let iconDestinationURL = resourcesURL.appendingPathComponent("\(Self.clientIconName).icns", isDirectory: false)
            try copyItemReplacingExisting(from: iconURL, to: iconDestinationURL)
        }

        let info: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": Self.clientAppName,
            "CFBundleExecutable": Self.clientWrapperExecutableName,
            "CFBundleIdentifier": Self.clientBundleIdentifier,
            "CFBundleIconFile": Self.clientIconName,
            "CFBundleIconName": Self.clientIconName,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": Self.clientAppName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "GCSupportsGameMode": true,
            "LSApplicationCategoryType": "public.app-category.games",
            "LSMinimumSystemVersion": "14.0",
            "LSSupportsGameMode": true,
            "NSHighResolutionCapable": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist", isDirectory: false), options: .atomic)
        return appURL
    }

    private func copyItemReplacingExisting(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func writeDetachedLaunchLog(
        _ command: LaunchCommand,
        logURL: URL?,
        capturesProcessOutput: Bool,
        appBundleURL: URL? = nil
    ) throws -> FileHandle? {
        guard let logURL else {
            return nil
        }
        let outputNote = appBundleURL == nil ? "" : "captured by mcpelauncher-client-wrapper\n"
        let appBundleText = appBundleURL.map { "app bundle: \($0.path)\n" } ?? ""
        let text = """
        executable: \(command.executableURL.path)
        \(appBundleText)arguments: \(command.arguments.joined(separator: " "))
        cwd: \(command.currentDirectoryURL.path)
        status: detached

        stdout/stderr:
        \(outputNote)
        """
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: logURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: logURL.path)
        guard capturesProcessOutput, appBundleURL == nil else {
            return nil
        }
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
        \(Self.redactedText(output))
        """
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: logURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: logURL.path)
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
        let redacted = redactedText(output)
        guard redacted.count > 4_000 else {
            return redacted
        }
        return String(redacted.suffix(4_000))
    }

    private static func redactedText(_ text: String) -> String {
        let redacted = text.replacingOccurrences(
            of: #"(?m)CRED=.*$"#,
            with: "CRED=<redacted>",
            options: .regularExpression
        )
        return redacted
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !isNoisyImageDecodeLine(String($0)) }
            .joined(separator: "\n")
    }

    private static func isNoisyImageDecodeLine(_ line: String) -> Bool {
        line.contains("NO LOG FILE! - Image failed to load from memory")
            && line.contains("Reason: unknown image type")
    }

    private static func redactedEnvironmentValue(key: String, value: String) -> String {
        switch key {
        case "MCPELAUNCHER_GOOGLE_EMAIL",
             "MCPELAUNCHER_GOOGLE_TOKEN",
             GoogleCredentialFileTransfer.environmentKey:
            return value.isEmpty ? "" : "<redacted>"
        default:
            return value
        }
    }
}

private struct LaunchCommand {
    var executableURL: URL
    var arguments: [String]
    var currentDirectoryURL: URL
    var environment: [String: String]
    var credentialFileURL: URL?
}

enum RuntimeClientWrapperEnvironment {
    static let executableKey = "MCPELAUNCHER_CLIENT_EXECUTABLE"
    static let workingDirectoryKey = "MCPELAUNCHER_CLIENT_WORKING_DIRECTORY"
    static let outputLogKey = "MCPELAUNCHER_CLIENT_OUTPUT_LOG"
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
