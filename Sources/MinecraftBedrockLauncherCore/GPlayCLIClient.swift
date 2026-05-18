import Foundation

public struct GPlayCLIClient: GooglePlayDownloading, @unchecked Sendable {
    private let gplayverURL: URL
    private let gplaydlURL: URL
    private let stateDirectoryURL: URL
    private let packageNameForAuth: String
    private let processRunner: ProcessRunning
    private let fileManager: FileManager

    public init(
        gplayverURL: URL,
        gplaydlURL: URL,
        stateDirectoryURL: URL,
        packageNameForAuth: String = "com.mojang.minecraftpe",
        processRunner: ProcessRunning = FoundationProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.gplayverURL = gplayverURL
        self.gplaydlURL = gplaydlURL
        self.stateDirectoryURL = stateDirectoryURL
        self.packageNameForAuth = packageNameForAuth
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    public func auth(_ request: GooglePlayAuthRequest) throws -> GoogleCredential {
        let deviceConfigURL = try prepareState(abi: "arm64-v8a")
        let input = "2\n\(request.oauthToken)\nY\n".data(using: .utf8)
        _ = try runTool(
            command: "gplayver auth",
            executableURL: gplayverURL,
            arguments: [
                "--interactive",
                "--device", deviceConfigURL.path,
                "--save-auth",
                "--accept-tos",
                "--app", packageNameForAuth
            ],
            input: input
        )

        let configURL = playDLConfigURL()
        let config = try readPlayDLConfig(at: configURL)
        guard let token = config.userToken, !token.isEmpty else {
            throw LauncherError.googlePlayCredentialNotSaved(configURL)
        }
        let email = config.userEmail?.isEmpty == false ? config.userEmail! : request.accountIdentifier
        guard !email.isEmpty else {
            throw LauncherError.googlePlayCredentialNotSaved(configURL)
        }
        return GoogleCredential(email: email, masterToken: token, userID: request.userID)
    }

    public func latest(
        packageName: String = "com.mojang.minecraftpe",
        abi: String = "arm64-v8a",
        credential: GoogleCredential
    ) throws -> LatestVersion {
        let deviceConfigURL = try prepareState(abi: abi)
        let result = try runTool(
            command: "gplayver",
            executableURL: gplayverURL,
            arguments: authenticatedArguments(
                deviceConfigURL: deviceConfigURL,
                credential: credential,
                tail: ["--app", packageName]
            )
        )
        return try parseLatestVersion(packageName: packageName, output: result.stdoutString + result.stderrString)
    }

    public func download(
        packageName: String = "com.mojang.minecraftpe",
        versionCode: Int,
        outputDirectory: URL,
        abi: String = "arm64-v8a",
        credential: GoogleCredential,
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) throws -> GooglePlayDownloadResponse {
        let deviceConfigURL = try prepareState(abi: abi)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let baseName = "\(packageName).\(versionCode)"
        try removeExistingDownloadedAPKs(in: outputDirectory, baseName: baseName)
        let outputURL = outputDirectory.appendingPathComponent("\(baseName).apk", isDirectory: false)

        let result = try runStreamingTool(
            command: "gplaydl",
            executableURL: gplaydlURL,
            arguments: authenticatedArguments(
                deviceConfigURL: deviceConfigURL,
                credential: credential,
                tail: [
                    "--app", packageName,
                    "--app-version", String(versionCode),
                    "--output", outputURL.path
                ]
            ),
            progress: progress
        )
        let files = try downloadedAPKs(in: outputDirectory, baseName: baseName)
        guard !files.isEmpty else {
            throw LauncherError.malformedGooglePlayToolOutput(
                command: "gplaydl",
                output: result.stdoutString + result.stderrString
            )
        }
        return GooglePlayDownloadResponse(packageName: packageName, versionCode: versionCode, files: files)
    }

    public func checkDownloadAccess(
        packageName: String = "com.mojang.minecraftpe",
        versionCode: Int,
        outputDirectory: URL,
        abi: String = "arm64-v8a",
        credential: GoogleCredential
    ) throws {
        let deviceConfigURL = try prepareState(abi: abi)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("\(packageName).\(versionCode).probe.apk", isDirectory: false)

        _ = try runStreamingTool(
            command: "gplaydl",
            executableURL: gplaydlURL,
            arguments: authenticatedArguments(
                deviceConfigURL: deviceConfigURL,
                credential: credential,
                tail: [
                    "--app", packageName,
                    "--app-version", String(versionCode),
                    "--output", outputURL.path
                ]
            ),
            stopAfterFirstProgress: true,
            progress: { _ in }
        )
    }

    private func authenticatedArguments(
        deviceConfigURL: URL,
        credential: GoogleCredential,
        tail: [String]
    ) -> [String] {
        [
            "--device", deviceConfigURL.path,
            "--accept-tos",
            "--email", credential.email,
            "--token", credential.masterToken
        ] + tail
    }

    private func prepareState(abi: String) throws -> URL {
        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        let deviceConfigURL = stateDirectoryURL.appendingPathComponent("device.conf", isDirectory: false)
        let contents = """
        config.native_platforms = [
            \(abi)
        ]

        """
        if (try? String(contentsOf: deviceConfigURL, encoding: .utf8)) != contents {
            try contents.write(to: deviceConfigURL, atomically: true, encoding: .utf8)
        }
        return deviceConfigURL
    }

    private func runTool(
        command: String,
        executableURL: URL,
        arguments: [String],
        input: Data? = nil
    ) throws -> ProcessResult {
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw LauncherError.googlePlayToolNotFound(executableURL)
        }
        let result = try processRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            input: input,
            currentDirectoryURL: stateDirectoryURL,
            environment: [:]
        )
        guard result.status == 0 else {
            let output = result.stderrString.isEmpty ? result.stdoutString : result.stderrString
            if isMinecraftNotOwnedOutput(output) {
                throw LauncherError.minecraftNotOwned(account: credentialFromArguments(arguments)?.email)
            }
            throw LauncherError.googlePlayToolFailed(
                command: command,
                status: result.status,
                output: output
            )
        }
        return result
    }

    private func runStreamingTool(
        command: String,
        executableURL: URL,
        arguments: [String],
        input: Data? = nil,
        stopAfterFirstProgress: Bool = false,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) throws -> ProcessResult {
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw LauncherError.googlePlayToolNotFound(executableURL)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = stateDirectoryURL
        process.environment = ProcessInfo.processInfo.environment

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

        let group = DispatchGroup()
        let outputTail = GPlayLockedStringTail()
        let errorTail = GPlayLockedStringTail()
        let progressParser = GPlayProgressParser()
        let progressSeen = GPlayLockedFlag()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let shouldContinue = autoreleasepool {
                    let chunk = stdout.fileHandleForReading.availableData
                    if chunk.isEmpty {
                        return false
                    }
                    outputTail.append(chunk)
                    progressParser.append(chunk) { event in
                        progressSeen.set()
                        progress(event)
                        if stopAfterFirstProgress, process.isRunning {
                            process.terminate()
                        }
                    }
                    return true
                }
                if !shouldContinue {
                    break
                }
            }
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let shouldContinue = autoreleasepool {
                    let chunk = stderr.fileHandleForReading.availableData
                    if chunk.isEmpty {
                        return false
                    }
                    errorTail.append(chunk)
                    progressParser.append(chunk) { event in
                        progressSeen.set()
                        progress(event)
                        if stopAfterFirstProgress, process.isRunning {
                            process.terminate()
                        }
                    }
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
            }
            ChildProcessRegistry.shared.unregister(process)
        }

        if let input, let stdin {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }

        process.waitUntilExit()
        group.wait()

        let stdoutData = outputTail.data()
        let stderrData = errorTail.data()
        let result = ProcessResult(status: process.terminationStatus, stdout: stdoutData, stderr: stderrData)
        progressParser.emitLastProgress(from: errorTail.text()) { event in
            progressSeen.set()
            progress(event)
        }

        guard result.status == 0 else {
            if stopAfterFirstProgress, progressSeen.value {
                return result
            }
            let output = combinedOutput(stdout: result.stdoutString, stderr: result.stderrString)
            if isMinecraftNotOwnedFailure(command: command, status: result.status, output: output) {
                throw LauncherError.minecraftNotOwned(account: credentialFromArguments(arguments)?.email)
            }
            throw LauncherError.googlePlayToolFailed(
                command: command,
                status: result.status,
                output: output
            )
        }
        return result
    }

    private func combinedOutput(stdout: String, stderr: String) -> String {
        [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func playDLConfigURL() -> URL {
        stateDirectoryURL.appendingPathComponent("playdl.conf", isDirectory: false)
    }

    private func readPlayDLConfig(at url: URL) throws -> (userEmail: String?, userToken: String?) {
        guard fileManager.fileExists(atPath: url.path) else {
            throw LauncherError.googlePlayCredentialNotSaved(url)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let values = GooglePlayToolConfig.parse(text)
        return (values["user_email"], values["user_token"])
    }

    private func parseLatestVersion(packageName: String, output: String) throws -> LatestVersion {
        var versionCode: Int?
        var versionName: String?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("version code:") {
                versionCode = Int(line.dropFirst("version code:".count).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("version string:") {
                versionName = line.dropFirst("version string:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let versionCode, let versionName, !versionName.isEmpty else {
            throw LauncherError.malformedGooglePlayToolOutput(command: "gplayver", output: output)
        }
        return LatestVersion(
            packageName: packageName,
            versionName: versionName,
            versionCode: versionCode,
            isBeta: false
        )
    }

    private func removeExistingDownloadedAPKs(in directory: URL, baseName: String) throws {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for file in files where isDownloadedAPK(file.lastPathComponent, baseName: baseName) {
            try fileManager.removeItem(at: file)
        }
    }

    private func downloadedAPKs(in directory: URL, baseName: String) throws -> [DownloadedAPK] {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try files
            .filter { isDownloadedAPK($0.lastPathComponent, baseName: baseName) }
            .sorted { left, right in
                if left.lastPathComponent == "\(baseName).apk" {
                    return true
                }
                if right.lastPathComponent == "\(baseName).apk" {
                    return false
                }
                return left.lastPathComponent < right.lastPathComponent
            }
            .map { file in
                let values = try file.resourceValues(forKeys: [.fileSizeKey])
                return DownloadedAPK(
                    component: componentName(for: file.lastPathComponent, baseName: baseName),
                    path: file,
                    size: values.fileSize.map(Int64.init)
                )
            }
    }

    private func isDownloadedAPK(_ fileName: String, baseName: String) -> Bool {
        fileName == "\(baseName).apk" ||
            (fileName.hasPrefix("\(baseName).") && fileName.hasSuffix(".apk"))
    }

    private func componentName(for fileName: String, baseName: String) -> String {
        guard fileName != "\(baseName).apk" else {
            return "base"
        }
        let prefix = "\(baseName)."
        let suffix = ".apk"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(suffix) else {
            return fileName
        }
        let start = fileName.index(fileName.startIndex, offsetBy: prefix.count)
        let end = fileName.index(fileName.endIndex, offsetBy: -suffix.count)
        let component = String(fileName[start..<end])
        return component.isEmpty ? "split" : component
    }

    private func credentialFromArguments(_ arguments: [String]) -> GoogleCredential? {
        guard let emailIndex = arguments.firstIndex(of: "--email"),
              arguments.indices.contains(arguments.index(after: emailIndex)) else {
            return nil
        }
        return GoogleCredential(email: arguments[arguments.index(after: emailIndex)], masterToken: "")
    }

    private func isMinecraftNotOwnedFailure(command: String, status: Int32, output: String) -> Bool {
        if command == "gplaydl", status == 11, output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return isMinecraftNotOwnedOutput(output)
    }

    private func isMinecraftNotOwnedOutput(_ output: String) -> Bool {
        let text = output.lowercased()
        let ownershipMarkers = [
            "not purchased",
            "not owned",
            "not acquired",
            "purchase",
            "ownership",
            "not available for this account",
            "item you were attempting to purchase",
            "purchase could not be found",
            "no entitlement",
            "not entitled",
            "server error 404"
        ]
        return ownershipMarkers.contains { text.contains($0) }
    }

}

private final class GPlayLockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private let limit = 256 * 1024

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        if data.count >= limit {
            storage = Data(data.suffix(limit))
            return
        }

        let availablePrefixBytes = max(limit - data.count, 0)
        if storage.count > availablePrefixBytes {
            storage = Data(storage.suffix(availablePrefixBytes))
        }
        storage.append(data)
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return Data(storage)
    }
}

private final class GPlayLockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}

private final class GPlayLockedStringTail: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    private let limit: Int

    init(limit: Int = 8192) {
        self.limit = limit
    }

    func append(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        append(text)
    }

    func append(_ text: String) {
        lock.lock()
        storage.append(text)
        if storage.count > limit {
            storage = String(storage.suffix(limit))
        }
        lock.unlock()
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func data() -> Data {
        Data(text().utf8)
    }
}

private final class GPlayProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var rollingOutput = ""
    private var lastBytesReceived: Int64?
    private var lastTotalBytes: Int64?
    private var completedComponentBytes: Int64 = 0
    private var firstSampleDate: Date?
    private var firstSampleBytes: Int64 = 0

    func append(_ data: Data, progress: @escaping @Sendable (DownloadProgress) -> Void) {
        guard let chunk = String(data: data, encoding: .utf8) else {
            return
        }
        emitLastProgress(from: chunk, progress: progress)
    }

    func emitLastProgress(from output: String, progress: @escaping @Sendable (DownloadProgress) -> Void) {
        guard !output.isEmpty,
              let event = parse(output) else {
            return
        }
        progress(event)
    }

    private func parse(_ output: String) -> DownloadProgress? {
        lock.lock()
        defer { lock.unlock() }

        rollingOutput.append(output)
        if rollingOutput.count > 8192 {
            rollingOutput = String(rollingOutput.suffix(8192))
        }

        guard let sample = parseLastDownloadedSample(in: rollingOutput) else {
            return nil
        }

        let rawBytesReceived = sample.receivedMiB * 1024 * 1024
        let rawTotalBytes = sample.totalMiB * 1024 * 1024
        guard rawBytesReceived != lastBytesReceived || rawTotalBytes != lastTotalBytes else {
            return nil
        }

        if let lastBytesReceived, let lastTotalBytes, rawBytesReceived < lastBytesReceived {
            completedComponentBytes += max(lastTotalBytes, lastBytesReceived)
            firstSampleDate = nil
        }

        let bytesReceived = completedComponentBytes + rawBytesReceived
        let totalBytes = completedComponentBytes + rawTotalBytes
        let now = Date()
        if firstSampleDate == nil {
            firstSampleDate = now
            firstSampleBytes = bytesReceived
        }
        lastBytesReceived = rawBytesReceived
        lastTotalBytes = rawTotalBytes

        var speed: Double?
        var eta: Double?
        if let firstSampleDate {
            let elapsed = now.timeIntervalSince(firstSampleDate)
            if elapsed > 0.2, bytesReceived > firstSampleBytes {
                speed = Double(bytesReceived - firstSampleBytes) / elapsed
                if let speed, speed > 1, totalBytes > bytesReceived {
                    eta = Double(totalBytes - bytesReceived) / speed
                }
            }
        }

        return DownloadProgress(
            bytesReceived: bytesReceived,
            totalBytes: totalBytes,
            speedBytesPerSecond: speed,
            etaSeconds: eta
        )
    }

    private func parseLastDownloadedSample(in output: String) -> (receivedMiB: Int64, totalMiB: Int64)? {
        guard let markerRange = output.range(of: "Downloaded ", options: [.backwards]),
              let bracketStart = output[markerRange.upperBound...].firstIndex(of: "["),
              let slash = output[bracketStart...].firstIndex(of: "/"),
              let bracketEnd = output[slash...].firstIndex(of: "]") else {
            return nil
        }

        let receivedText = output[output.index(after: bracketStart)..<slash]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let totalAndUnit = output[output.index(after: slash)..<bracketEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let totalText = totalAndUnit.split(separator: " ").first.map(String.init) ?? totalAndUnit

        guard let receivedMiB = Int64(receivedText),
              let totalMiB = Int64(totalText) else {
            return nil
        }
        return (receivedMiB, totalMiB)
    }
}

private enum GooglePlayToolConfig {
    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard !line.hasPrefix(";"),
                  let separator = line.range(of: " = ") else {
                continue
            }
            let key = String(line[..<separator.lowerBound])
            let value = String(line[separator.upperBound...])
            values[unescapeKey(key)] = unescapeValue(value)
        }
        return values
    }

    private static func unescapeKey(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\\\\"#, with: #"\"#)
            .replacingOccurrences(of: #"\\="#, with: "=")
            .replacingOccurrences(of: #"\\;"#, with: ";")
    }

    private static func unescapeValue(_ value: String) -> String {
        guard value.first == "\"", value.last == "\"" else {
            return value
        }
        let inner = value.dropFirst().dropLast()
        return inner
            .replacingOccurrences(of: #"\\\\"#, with: #"\"#)
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\\n"#, with: "\n")
    }
}
