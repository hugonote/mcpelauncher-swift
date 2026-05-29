import Foundation

public enum GoogleCredentialFileTransfer {
    public static let environmentKey = "MCPELAUNCHER_GOOGLE_CREDENTIAL_FILE"

    public static func writeCredential(
        _ credential: GoogleCredential,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("mcpelauncher-credential-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )

        let fileURL = directoryURL.appendingPathComponent("credential.json", isDirectory: false)
        let runtimeCredential = GooglePlayCredentialInput(
            email: credential.email,
            masterToken: credential.masterToken
        )
        try JSONEncoder().encode(runtimeCredential).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: fileURL.path)
        return fileURL
    }

    public static func credentialFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> GoogleCredential? {
        guard let path = environment[environmentKey], !path.isEmpty else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: path, isDirectory: false)
        defer {
            try? fileManager.removeItem(at: fileURL.deletingLastPathComponent())
        }
        let data = try Data(contentsOf: fileURL)
        let credential = try JSONDecoder().decode(GooglePlayCredentialInput.self, from: data)
        return GoogleCredential(email: credential.email, masterToken: credential.masterToken)
    }

    public static func removeCredentialFile(at fileURL: URL?, fileManager: FileManager = .default) {
        guard let fileURL else {
            return
        }
        try? fileManager.removeItem(at: fileURL.deletingLastPathComponent())
    }

    public static func scheduleCredentialFileRemoval(
        at fileURL: URL?,
        after delay: TimeInterval,
        fileManager: FileManager = .default
    ) {
        guard let fileURL else {
            return
        }

        if delay <= 0 {
            removeCredentialFile(at: fileURL, fileManager: fileManager)
            return
        }

        let directoryPath = fileURL.deletingLastPathComponent().path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep \"$1\"; rm -rf -- \"$2\"",
            "mcpelauncher-credential-cleanup",
            String(delay),
            directoryPath
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
