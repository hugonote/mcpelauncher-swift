import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class RuntimeManagerTests: XCTestCase {
    func testDefaultRuntimeManifestUsesSwiftLauncherRelease() {
        XCTAssertEqual(
            RuntimeManager.defaultRuntimeManifestURL.absoluteString,
            "https://github.com/hugonote/mcpelauncher-swift/releases/latest/download/runtime-manifest.json"
        )
    }

    func testSelectRuntimeAssetPrefersModernMacOSDMG() {
        let assets = [
            GitHubAsset(
                name: "Minecraft_Bedrock_Launcher_v1.7.4-macOS-x86_64-0.0.565_macOS_10.10.0.dmg",
                size: 120,
                digest: nil,
                browserDownloadURL: "https://example.com/old.dmg"
            ),
            GitHubAsset(
                name: "Minecraft.Bedrock.Launcher0.2.564-0.2.563.delta",
                size: 1,
                digest: nil,
                browserDownloadURL: "https://example.com/update.delta"
            ),
            GitHubAsset(
                name: "Minecraft_Bedrock_Launcher_v1.7.4-macOS-x86_64-0.2.565_macOS_10.13.0.dmg",
                size: 140,
                digest: "sha256:abc",
                browserDownloadURL: "https://example.com/runtime.dmg"
            ),
            GitHubAsset(
                name: "Minecraft_Bedrock_Launcher_v1.x-nightly-macOS-x86_64-0.2.1067_macOS_10.13.0.dmg",
                size: 130,
                digest: "sha256:def",
                browserDownloadURL: "https://example.com/nightly.dmg"
            )
        ]

        let selected = RuntimeManager.selectRuntimeAsset(from: assets)

        XCTAssertEqual(selected?.browserDownloadURL, "https://example.com/nightly.dmg")
        XCTAssertEqual(selected?.sha256Digest, "def")
    }

    func testRuntimeManifestResolvesRelativeAssetURL() throws {
        let manifest = RuntimeReleaseManifest(
            version: "upstream-abc123-swift2",
            assetName: nil,
            downloadURL: "mcpelauncher-runtime-macos-arm64-abc123.zip",
            sha256: "deadbeef",
            size: 42
        )

        let release = try RuntimeManager.runtimeRelease(
            from: manifest,
            manifestURL: URL(string: "https://github.com/example/repo/releases/download/nightly/runtime-manifest.json")!
        )

        XCTAssertEqual(release.version, "upstream-abc123-swift2")
        XCTAssertEqual(release.assetName, "mcpelauncher-runtime-macos-arm64-abc123.zip")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://github.com/example/repo/releases/download/nightly/mcpelauncher-runtime-macos-arm64-abc123.zip")
        XCTAssertEqual(release.sha256, "deadbeef")
        XCTAssertEqual(release.size, 42)
    }

    func testRuntimeManifestResolvesRelativeFileAssetURL() throws {
        let manifest = RuntimeReleaseManifest(
            version: "local",
            assetName: nil,
            downloadURL: "runtime.zip",
            sha256: nil,
            size: nil
        )

        let release = try RuntimeManager.runtimeRelease(
            from: manifest,
            manifestURL: URL(fileURLWithPath: "/var/tmp/runtime-manifest.json")
        )

        XCTAssertTrue(release.downloadURL.isFileURL)
        XCTAssertEqual(release.downloadURL.lastPathComponent, "runtime.zip")
        XCTAssertEqual(release.assetName, "runtime.zip")
    }

    func testRuntimeLauncherAcceptsMacOSAppContentsLayout() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client", isDirectory: false)
        try writeExecutable(executableURL)

        let resolved = try RuntimeLauncher().runtimeExecutable(in: runtimeURL)

        XCTAssertEqual(resolved, executableURL)
    }

    func testRuntimeLauncherPrefersCMakeInstallLayout() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("bin/mcpelauncher-client", isDirectory: false)
        let legacyExecutableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client-arm64-v8a", isDirectory: false)
        let versionURL = temp.url.appendingPathComponent("Game", isDirectory: true)
        try writeExecutable(executableURL)
        try writeExecutable(legacyExecutableURL)
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)

        final class CaptureBox: @unchecked Sendable {
            var executableURL: URL?
            var currentDirectoryURL: URL?
        }
        let capture = CaptureBox()
        let runner = MockProcessRunner { executableURL, _, _, currentDirectoryURL, _ in
            capture.executableURL = executableURL
            capture.currentDirectoryURL = currentDirectoryURL
            return ProcessResult(status: 0, stdout: Data(), stderr: Data())
        }
        let version = InstalledVersion(versionName: "1.26.20.4", versionCode: 972602004, installPath: versionURL)

        try RuntimeLauncher(processRunner: runner).launch(runtimePath: runtimeURL, version: version)

        XCTAssertEqual(try RuntimeLauncher().runtimeExecutable(in: runtimeURL), executableURL)
        XCTAssertEqual(capture.executableURL, executableURL)
        XCTAssertEqual(capture.currentDirectoryURL, runtimeURL)
    }

    func testRuntimeLauncherPrefersAppleSiliconClient() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let x86ExecutableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client", isDirectory: false)
        let armExecutableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client-arm64-v8a", isDirectory: false)
        try writeExecutable(x86ExecutableURL)
        try writeExecutable(armExecutableURL)

        let resolved = try RuntimeLauncher().runtimeExecutable(in: runtimeURL)

        XCTAssertEqual(resolved, armExecutableURL)
    }

    func testRuntimeLauncherAcceptsCopiedMacOSBuilderRuntimeLayout() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let runtimeRootURL = runtimeURL.appendingPathComponent("Resources/Minecraft Bedrock", isDirectory: true)
        let executableURL = runtimeRootURL.appendingPathComponent("mcpelauncher-client/mcpelauncher-client", isDirectory: false)
        let versionURL = temp.url.appendingPathComponent("Game", isDirectory: true)
        try writeExecutable(executableURL)
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)

        final class CaptureBox: @unchecked Sendable {
            var currentDirectoryURL: URL?
        }
        let capture = CaptureBox()
        let runner = MockProcessRunner { _, _, _, currentDirectoryURL, _ in
            capture.currentDirectoryURL = currentDirectoryURL
            return ProcessResult(status: 0, stdout: Data(), stderr: Data())
        }
        let version = InstalledVersion(versionName: "1.26.20.4", versionCode: 972602004, installPath: versionURL)

        try RuntimeLauncher(processRunner: runner).launch(runtimePath: runtimeURL, version: version)

        XCTAssertEqual(try RuntimeLauncher().runtimeExecutable(in: runtimeURL), executableURL)
        XCTAssertEqual(capture.currentDirectoryURL, runtimeRootURL)
    }

    func testRuntimeInstallRejectsSplitAndroidShimLibraries() async throws {
        let temp = try TemporaryDirectory()
        let paths = AppPaths(baseURL: temp.url.appendingPathComponent("AppData", isDirectory: true))
        let archiveURL = temp.url.appendingPathComponent("runtime.zip", isDirectory: false)
        try Data("archive".utf8).write(to: archiveURL)
        let runner = MockProcessRunner { _, arguments, _, _, _ in
            let extractURL = URL(fileURLWithPath: arguments[3], isDirectory: true)
            let runtimeURL = extractURL.appendingPathComponent("RuntimeRoot", isDirectory: true)
            try writeExecutable(runtimeURL.appendingPathComponent("bin/mcpelauncher-client", isDirectory: false))
            try writeTestFile(runtimeURL.appendingPathComponent(
                "share/mcpelauncher/lib/arm64-v8a/libc.so",
                isDirectory: false
            ))
            try writeTestFile(runtimeURL.appendingPathComponent(
                "Resources/mcpelauncher/lib/arm64-v8a/liblog.so",
                isDirectory: false
            ))
            try writeTestGraphicsFrameworks(in: runtimeURL)
            return ProcessResult(status: 0, stdout: Data(), stderr: Data())
        }
        let manager = RuntimeManager(paths: paths, processRunner: runner)
        let release = RuntimeRelease(version: "test", assetName: "runtime.zip", downloadURL: archiveURL)

        do {
            _ = try await manager.install(release)
            XCTFail("Expected runtime install to reject split Android shim libraries.")
        } catch LauncherError.runtimeInstallFailed(let message) {
            XCTAssertTrue(message.contains("Android shim libraries"))
        }
    }

    func testRuntimeLauncherPassesCompatibilityPatchAndRuntimeDataPath() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client-arm64-v8a", isDirectory: false)
        let versionURL = temp.url.appendingPathComponent("Game", isDirectory: true)
        let patchURL = temp.url.appendingPathComponent("Patch", isDirectory: true)
        let dataURL = temp.url.appendingPathComponent("Data", isDirectory: true)
        let cacheURL = temp.url.appendingPathComponent("Cache", isDirectory: true)
        let helpersURL = temp.url.appendingPathComponent("Helpers", isDirectory: true)
        try writeExecutable(executableURL)
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: patchURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: runtimeURL.appendingPathComponent("Resources/mcpelauncher", isDirectory: true),
            withIntermediateDirectories: true
        )

        final class CaptureBox: @unchecked Sendable {
            var arguments: [String] = []
            var environment: [String: String] = [:]
            var credentialFromFile: GoogleCredential?
            var credentialFilePath: String?
        }
        let capture = CaptureBox()
        let runner = MockProcessRunner { _, arguments, _, _, environment in
            capture.arguments = arguments
            capture.environment = environment
            if let path = environment[GoogleCredentialFileTransfer.environmentKey], !path.isEmpty {
                capture.credentialFilePath = path
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                capture.credentialFromFile = try JSONDecoder().decode(GoogleCredential.self, from: data)
            }
            return ProcessResult(status: 0, stdout: Data(), stderr: Data())
        }
        let version = InstalledVersion(versionName: "1.26.20.4", versionCode: 972602004, installPath: versionURL)

        try RuntimeLauncher(processRunner: runner).launch(
            runtimePath: runtimeURL,
            version: version,
            compatibilityPatchPath: patchURL,
            dataPath: dataURL,
            cachePath: cacheURL,
            credentialsHelperDirectory: helpersURL,
            googleCredential: GoogleCredential(email: "u@example.com", masterToken: "master")
        )

        XCTAssertTrue(capture.arguments.contains("-fes"))
        XCTAssertTrue(capture.arguments.contains("-m"))
        XCTAssertTrue(capture.arguments.contains(patchURL.path))
        XCTAssertTrue(capture.arguments.contains("-dd"))
        XCTAssertTrue(capture.arguments.contains(dataURL.path))
        XCTAssertTrue(capture.arguments.contains("-dc"))
        XCTAssertTrue(capture.arguments.contains(cacheURL.path))
        XCTAssertEqual(capture.environment["XDG_DATA_DIRS"]?.components(separatedBy: ":").first, runtimeURL.appendingPathComponent("Resources").path)
        XCTAssertEqual(capture.environment["MCPELAUNCHER_GOOGLE_EMAIL"], "")
        XCTAssertEqual(capture.environment["MCPELAUNCHER_GOOGLE_TOKEN"], "")
        XCTAssertEqual(capture.credentialFromFile?.email, "u@example.com")
        XCTAssertEqual(capture.credentialFromFile?.masterToken, "master")
        XCTAssertNotNil(capture.credentialFilePath)
        XCTAssertFalse(capture.credentialFilePath?.contains("master") ?? true)
        if let credentialFilePath = capture.credentialFilePath {
            XCTAssertFalse(FileManager.default.fileExists(atPath: credentialFilePath))
        }
        XCTAssertEqual(capture.environment["PATH"]?.components(separatedBy: ":").first, helpersURL.path)
    }

    func testRuntimeLauncherWritesLogAndThrowsForNonZeroExit() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client-arm64-v8a", isDirectory: false)
        let versionURL = temp.url.appendingPathComponent("Game", isDirectory: true)
        let logURL = temp.url.appendingPathComponent("Logs/launch.log", isDirectory: false)
        try writeExecutable(executableURL)
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)

        let runner = MockProcessRunner { _, _, _, _, _ in
            ProcessResult(
                status: 6,
                stdout: Data("stdout line\n12:23:24 Warn  [Minecraft] NO LOG FILE! - Image failed to load from memory \tReason: unknown image type\nCRED=u@example.com:master-token\n".utf8),
                stderr: Data("Failed to find data file: lib/arm64-v8a/libc.so".utf8)
            )
        }
        let version = InstalledVersion(versionName: "1.26.21.1", versionCode: 972602101, installPath: versionURL)

        XCTAssertThrowsError(
            try RuntimeLauncher(processRunner: runner).launch(runtimePath: runtimeURL, version: version, logURL: logURL)
        ) { error in
            guard case LauncherError.gameLaunchFailed(let status, let capturedLogURL, let outputTail) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 6)
            XCTAssertEqual(capturedLogURL, logURL)
            XCTAssertTrue(outputTail.contains("Failed to find data file"))
            XCTAssertFalse(outputTail.contains("NO LOG FILE! - Image failed to load from memory"))
            XCTAssertFalse(outputTail.contains("master-token"))
            XCTAssertTrue(outputTail.contains("CRED=<redacted>"))
        }
        let log = try String(contentsOf: logURL)
        XCTAssertTrue(log.contains("status: 6"))
        XCTAssertTrue(log.contains("stdout line"))
        XCTAssertTrue(log.contains("Failed to find data file"))
        XCTAssertFalse(log.contains("NO LOG FILE! - Image failed to load from memory"))
        XCTAssertFalse(log.contains("master-token"))
        XCTAssertTrue(log.contains("CRED=<redacted>"))
    }

    func testDetachedLaunchCapturesProcessOutputWhenCredentialHelperMayBeRequested() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client-arm64-v8a", isDirectory: false)
        let versionURL = temp.url.appendingPathComponent("Game", isDirectory: true)
        let helpersURL = temp.url.appendingPathComponent("Helpers", isDirectory: true)
        let logURL = temp.url.appendingPathComponent("Logs/launch.log", isDirectory: false)
        try writeExecutable(
            executableURL,
            contents: """
            #!/bin/zsh
            print 'CRED=u@example.com:master-token'
            """
        )
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helpersURL, withIntermediateDirectories: true)
        let version = InstalledVersion(versionName: "1.26.21.1", versionCode: 972602101, installPath: versionURL)

        try RuntimeLauncher().launchDetached(
            runtimePath: runtimeURL,
            version: version,
            credentialsHelperDirectory: helpersURL,
            googleCredential: GoogleCredential(email: "u@example.com", masterToken: "master"),
            logURL: logURL
        )

        var log = try String(contentsOf: logURL)
        for _ in 0..<50 where !log.contains("CRED=u@example.com:master-token") {
            Thread.sleep(forTimeInterval: 0.02)
            log = try String(contentsOf: logURL)
        }
        XCTAssertTrue(log.contains("CRED=u@example.com:master-token"))
        let attributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testDetachedLaunchUsesGeneratedGameModeAppBundleWhenWrapperIsAvailable() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("bin/mcpelauncher-client", isDirectory: false)
        let versionURL = temp.url.appendingPathComponent("Game", isDirectory: true)
        let wrapperURL = temp.url.appendingPathComponent("Helpers/mcpelauncher-client-wrapper", isDirectory: false)
        let iconURL = temp.url.appendingPathComponent("Icon/minecraft-bedrock.icns", isDirectory: false)
        let logURL = temp.url.appendingPathComponent("Logs/launch.log", isDirectory: false)
        try writeExecutable(executableURL)
        try writeExecutable(wrapperURL)
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("icon".utf8).write(to: iconURL)
        let appLauncher = MockRuntimeApplicationLauncher()
        let launcher = RuntimeLauncher(applicationLauncher: appLauncher)
        let version = InstalledVersion(versionName: "1.26.20.4", versionCode: 972602004, installPath: versionURL)

        try launcher.launchDetached(
            runtimePath: runtimeURL,
            version: version,
            logURL: logURL,
            clientWrapperExecutableURL: wrapperURL,
            clientWrapperIconURL: iconURL
        )

        XCTAssertEqual(appLauncher.launches.count, 1)
        let launch = try XCTUnwrap(appLauncher.launches.first)
        XCTAssertEqual(launch.appURL, runtimeURL.appendingPathComponent("Minecraft Bedrock.app", isDirectory: true))
        XCTAssertEqual(launch.environment[RuntimeClientWrapperEnvironment.executableKey], executableURL.path)
        XCTAssertEqual(launch.environment[RuntimeClientWrapperEnvironment.workingDirectoryKey], runtimeURL.path)
        XCTAssertEqual(launch.environment[RuntimeClientWrapperEnvironment.outputLogKey], logURL.path)
        XCTAssertEqual(launch.arguments, ["--disable-fmod", "-fes", "-dg", versionURL.path])

        let appURL = launch.appURL
        let copiedWrapperURL = appURL.appendingPathComponent("Contents/MacOS/mcpelauncher-client-wrapper", isDirectory: false)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: copiedWrapperURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: appURL.appendingPathComponent("Contents/Resources/minecraft-bedrock.icns", isDirectory: false).path
        ))

        let infoURL = appURL.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        let infoData = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "mcpelauncher-client-wrapper")
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "local.minecraft.bedrock.swiftlauncher.client")
        XCTAssertEqual(info["LSApplicationCategoryType"] as? String, "public.app-category.games")
        XCTAssertEqual(info["LSSupportsGameMode"] as? Bool, true)
        XCTAssertEqual(info["GCSupportsGameMode"] as? Bool, true)

        let log = try String(contentsOf: logURL)
        XCTAssertTrue(log.contains("app bundle: \(appURL.path)"))
        XCTAssertTrue(log.contains("captured by mcpelauncher-client-wrapper"))
    }

    func testDetachedLaunchDelegatesCredentialCleanupToWrapper() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("bin/mcpelauncher-client", isDirectory: false)
        let versionURL = temp.url.appendingPathComponent("Game", isDirectory: true)
        let wrapperURL = temp.url.appendingPathComponent("Helpers/mcpelauncher-client-wrapper", isDirectory: false)
        let logURL = temp.url.appendingPathComponent("Logs/launch.log", isDirectory: false)
        try writeExecutable(executableURL)
        try writeExecutable(wrapperURL)
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)
        let appLauncher = MockRuntimeApplicationLauncher()
        let launcher = RuntimeLauncher(
            applicationLauncher: appLauncher,
            detachedCredentialCleanupDelay: 0
        )
        let version = InstalledVersion(versionName: "1.26.20.4", versionCode: 972602004, installPath: versionURL)

        try launcher.launchDetached(
            runtimePath: runtimeURL,
            version: version,
            googleCredential: GoogleCredential(email: "u@example.com", masterToken: "master"),
            logURL: logURL,
            clientWrapperExecutableURL: wrapperURL
        )

        let launch = try XCTUnwrap(appLauncher.launches.first)
        let credentialPath = try XCTUnwrap(launch.environment[GoogleCredentialFileTransfer.environmentKey])
        defer {
            GoogleCredentialFileTransfer.removeCredentialFile(
                at: URL(fileURLWithPath: credentialPath, isDirectory: false)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: credentialPath))
        XCTAssertEqual(launch.environment[RuntimeClientWrapperEnvironment.outputLogKey], logURL.path)
    }

    func testRuntimeWarmUpTerminatesAfterPairIPLoads() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client-arm64-v8a", isDirectory: false)
        try writeExecutable(
            executableURL,
            contents: """
            #!/bin/zsh
            print '17:00:00 Info  [MinecraftUtils] Loaded libpairipcore'
            sleep 10
            """
        )
        let version = try makeWarmUpVersion(in: temp.url)

        let result = try RuntimeLauncher().warmUpFirstLaunch(
            runtimePath: runtimeURL,
            version: version,
            compatibilityPatchPath: temp.url.appendingPathComponent("Patch", isDirectory: true),
            dataPath: temp.url.appendingPathComponent("Data", isDirectory: true),
            cachePath: temp.url.appendingPathComponent("Cache", isDirectory: true),
            credentialsHelperDirectory: temp.url.appendingPathComponent("Helpers", isDirectory: true),
            googleCredential: GoogleCredential(email: "u@example.com", masterToken: "master"),
            timeout: 2
        )

        XCTAssertEqual(result, .loadedPairIP)
    }

    func testRuntimeWarmUpAcceptsFirstRunPairIPCrashAfterTokenIsWritten() throws {
        let temp = try TemporaryDirectory()
        let runtimeURL = temp.url.appendingPathComponent("Runtime", isDirectory: true)
        let executableURL = runtimeURL.appendingPathComponent("MacOS/mcpelauncher-client-arm64-v8a", isDirectory: false)
        try writeExecutable(
            executableURL,
            contents: """
            #!/bin/zsh
            data_dir=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "-dd" ]]; then
                data_dir="$2"
                shift 2
              else
                shift
              fi
            done
            mkdir -p "$data_dir"
            print -n token > "$data_dir/pass.token"
            print 'Starting download...'
            print 'linker: mcpelauncher_linker_notifylldb /tmp/libpairipcore.so 0x123'
            print 'Signal 11 received'
            exit 11
            """
        )
        let version = try makeWarmUpVersion(in: temp.url)

        let result = try RuntimeLauncher().warmUpFirstLaunch(
            runtimePath: runtimeURL,
            version: version,
            compatibilityPatchPath: temp.url.appendingPathComponent("Patch", isDirectory: true),
            dataPath: temp.url.appendingPathComponent("Data", isDirectory: true),
            cachePath: temp.url.appendingPathComponent("Cache", isDirectory: true),
            credentialsHelperDirectory: temp.url.appendingPathComponent("Helpers", isDirectory: true),
            googleCredential: GoogleCredential(email: "u@example.com", masterToken: "master"),
            timeout: 2
        )

        XCTAssertEqual(result, .acceptedFirstRunPairIPCrash)
    }

    private func makeWarmUpVersion(in rootURL: URL) throws -> InstalledVersion {
        let versionURL = rootURL.appendingPathComponent("Game", isDirectory: true)
        try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Patch", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Helpers", isDirectory: true),
            withIntermediateDirectories: true
        )
        return InstalledVersion(versionName: "1.26.20.4", versionCode: 972602004, installPath: versionURL)
    }
}

private func writeTestFile(_ url: URL, contents: String = "") throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
}

private func writeTestGraphicsFrameworks(in runtimeURL: URL) throws {
    let rootURL = runtimeURL.appendingPathComponent("Frameworks/mvk-angle", isDirectory: true)
    try writeTestFile(rootURL.appendingPathComponent("libEGL.dylib", isDirectory: false))
    try writeTestFile(rootURL.appendingPathComponent("libGLESv2.dylib", isDirectory: false))
    try writeTestFile(rootURL.appendingPathComponent("MoltenVK_icd.json", isDirectory: false))
}
