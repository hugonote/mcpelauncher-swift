import Foundation
import MinecraftBedrockLauncherCore

struct LoginCoordinator: Sendable {
    var googlePlay: any GooglePlayDownloading
    var credentialStore: CredentialStore

    func completeLogin(email: String, userID: String, oauthToken: String) async throws -> GoogleCredential {
        let request = GooglePlayAuthRequest(
            accountIdentifier: email,
            userID: userID,
            oauthToken: oauthToken
        )
        let credential = try await googlePlay.auth(request)
        try credentialStore.saveCredential(credential)
        return credential
    }
}

struct MinecraftDownloadCoordinator: Sendable {
    static let packageName = "com.mojang.minecraftpe"
    static let abi = "arm64-v8a"

    var googlePlay: any GooglePlayDownloading
    var processRunner: ProcessRunning

    func latestVersion(credential: GoogleCredential) async throws -> LatestVersion {
        try await googlePlay.latest(
            packageName: Self.packageName,
            abi: Self.abi,
            credential: credential
        )
    }

    func checkDownloadAccess(
        for version: LatestVersion,
        credential: GoogleCredential,
        outputDirectory: URL
    ) async throws {
        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }
        try await googlePlay.checkDownloadAccess(
            packageName: Self.packageName,
            versionCode: version.versionCode,
            outputDirectory: outputDirectory,
            abi: Self.abi,
            credential: credential
        )
    }

    func download(
        _ version: LatestVersion,
        credential: GoogleCredential,
        outputDirectory: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> GooglePlayDownloadResponse {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        return try await googlePlay.download(
            packageName: Self.packageName,
            versionCode: version.versionCode,
            outputDirectory: outputDirectory,
            abi: Self.abi,
            credential: credential,
            progress: progress
        )
    }

    func install(
        downloadedAPKs: [DownloadedAPK],
        latestVersion: LatestVersion,
        versionsDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> InstalledVersion {
        let installer = GameInstaller(processRunner: processRunner)
        return try await runOffMain {
            try installer.install(
                downloadedAPKs: downloadedAPKs,
                latestVersion: latestVersion,
                versionsDirectory: versionsDirectory,
                progress: progress
            )
        }
    }
}

struct RuntimeInstallCoordinator: Sendable {
    var manager: RuntimeManager

    func installedState(fallbackDetail: String) -> RuntimeState? {
        guard manager.hasInstalledRuntime() else {
            return nil
        }
        if let metadata = manager.installedMetadata() {
            return RuntimeState(phase: .ready, version: metadata.version, detail: fallbackDetail)
        }
        return RuntimeState(phase: .ready, version: "installed", detail: fallbackDetail)
    }

    func installLatest(progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> RuntimeMetadata {
        try await manager.installLatest(progress: progress)
    }

    func resolveLatestRelease() async throws -> RuntimeRelease {
        try await manager.resolveLatestRelease()
    }

    func install(
        _ release: RuntimeRelease,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> RuntimeMetadata {
        try await manager.install(release, progress: progress)
    }
}

struct LaunchCoordinator: Sendable {
    var launcher: RuntimeLauncher

    func launchDetached(
        runtimePath: URL,
        version: InstalledVersion,
        compatibilityPatchPath: URL,
        dataPath: URL,
        cachePath: URL,
        credentialsHelperDirectory: URL,
        googleCredential: GoogleCredential,
        logURL: URL?,
        clientWrapperExecutableURL: URL?,
        clientWrapperIconURL: URL?
    ) async throws {
        try await runOffMain {
            try launcher.launchDetached(
                runtimePath: runtimePath,
                version: version,
                compatibilityPatchPath: compatibilityPatchPath,
                dataPath: dataPath,
                cachePath: cachePath,
                credentialsHelperDirectory: credentialsHelperDirectory,
                googleCredential: googleCredential,
                logURL: logURL,
                clientWrapperExecutableURL: clientWrapperExecutableURL,
                clientWrapperIconURL: clientWrapperIconURL
            )
        }
    }
}
