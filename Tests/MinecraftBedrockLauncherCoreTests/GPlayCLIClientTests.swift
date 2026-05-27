import Foundation
import XCTest
@testable import MinecraftBedrockLauncherCore

final class GPlayCLIClientTests: XCTestCase {
    func testAuthRunsGPlayverWithAccessTokenAndReadsSavedToken() throws {
        let temp = try TemporaryDirectory()
        let gplayverURL = temp.url.appendingPathComponent("gplayver")
        let gplaydlURL = temp.url.appendingPathComponent("gplaydl")
        try writeExecutable(gplayverURL)
        try writeExecutable(gplaydlURL)

        let runner = MockProcessRunner { executableURL, arguments, input, currentDirectoryURL, _ in
            XCTAssertEqual(executableURL, gplayverURL)
            XCTAssertTrue(arguments.contains("--access-token-stdin"))
            XCTAssertFalse(arguments.contains("oauth-token"))
            XCTAssertFalse(arguments.contains("--interactive"))
            XCTAssertTrue(arguments.contains("--save-auth"))
            XCTAssertTrue(arguments.contains("--accept-tos"))
            XCTAssertEqual(String(data: input ?? Data(), encoding: .utf8), "oauth-token\n")
            let configURL = try XCTUnwrap(currentDirectoryURL)
                .appendingPathComponent("playdl.conf", isDirectory: false)
            try "user_email = user@example.com\nuser_token = master-token\n"
                .write(to: configURL, atomically: true, encoding: .utf8)
            return ProcessResult(status: 0, stdout: Data(), stderr: Data())
        }
        let client = GPlayCLIClient(
            gplayverURL: gplayverURL,
            gplaydlURL: gplaydlURL,
            stateDirectoryURL: temp.url.appendingPathComponent("state", isDirectory: true),
            processRunner: runner
        )

        let credential = try client.auth(
            GooglePlayAuthRequest(accountIdentifier: "", userID: "user-id", oauthToken: "oauth-token")
        )

        XCTAssertEqual(credential.email, "user@example.com")
        XCTAssertEqual(credential.masterToken, "master-token")
        XCTAssertEqual(credential.userID, "user-id")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temp.url
                    .appendingPathComponent("state", isDirectory: true)
                    .appendingPathComponent("playdl.conf", isDirectory: false)
                    .path
            )
        )
    }

    func testAuthRemovesSavedTokenWhenGPlayverFails() throws {
        let temp = try TemporaryDirectory()
        let gplayverURL = temp.url.appendingPathComponent("gplayver")
        let gplaydlURL = temp.url.appendingPathComponent("gplaydl")
        try writeExecutable(gplayverURL)
        try writeExecutable(gplaydlURL)
        let stateURL = temp.url.appendingPathComponent("state", isDirectory: true)
        let configURL = stateURL.appendingPathComponent("playdl.conf", isDirectory: false)

        let runner = MockProcessRunner { _, _, _, currentDirectoryURL, _ in
            let configURL = try XCTUnwrap(currentDirectoryURL)
                .appendingPathComponent("playdl.conf", isDirectory: false)
            try "user_email = user@example.com\nuser_token = master-token\n"
                .write(to: configURL, atomically: true, encoding: .utf8)
            return ProcessResult(status: 1, stdout: Data(), stderr: Data("auth failed".utf8))
        }
        let client = GPlayCLIClient(
            gplayverURL: gplayverURL,
            gplaydlURL: gplaydlURL,
            stateDirectoryURL: stateURL,
            processRunner: runner
        )

        XCTAssertThrowsError(
            try client.auth(
                GooglePlayAuthRequest(accountIdentifier: "user@example.com", userID: "user-id", oauthToken: "oauth-token")
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testAuthDoesNotReuseStaleSavedTokenWhenGPlayverWritesNothing() throws {
        let temp = try TemporaryDirectory()
        let gplayverURL = temp.url.appendingPathComponent("gplayver")
        let gplaydlURL = temp.url.appendingPathComponent("gplaydl")
        try writeExecutable(gplayverURL)
        try writeExecutable(gplaydlURL)
        let stateURL = temp.url.appendingPathComponent("state", isDirectory: true)
        let configURL = stateURL.appendingPathComponent("playdl.conf", isDirectory: false)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
        try "user_email = stale@example.com\nuser_token = stale-token\n"
            .write(to: configURL, atomically: true, encoding: .utf8)

        let runner = MockProcessRunner { _, _, _, _, _ in
            ProcessResult(status: 0, stdout: Data(), stderr: Data())
        }
        let client = GPlayCLIClient(
            gplayverURL: gplayverURL,
            gplaydlURL: gplaydlURL,
            stateDirectoryURL: stateURL,
            processRunner: runner
        )

        XCTAssertThrowsError(
            try client.auth(
                GooglePlayAuthRequest(accountIdentifier: "user@example.com", userID: "user-id", oauthToken: "oauth-token")
            )
        ) { error in
            guard case LauncherError.googlePlayCredentialNotSaved(let url) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url, configURL)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testLatestRunsGPlayverAndParsesVersionOutput() throws {
        let temp = try TemporaryDirectory()
        let gplayverURL = temp.url.appendingPathComponent("gplayver")
        let gplaydlURL = temp.url.appendingPathComponent("gplaydl")
        try writeExecutable(gplayverURL)
        try writeExecutable(gplaydlURL)
        let stateURL = temp.url.appendingPathComponent("state", isDirectory: true)

        let runner = MockProcessRunner { executableURL, arguments, input, currentDirectoryURL, _ in
            XCTAssertEqual(executableURL, gplayverURL)
            XCTAssertEqual(String(data: input ?? Data(), encoding: .utf8), "master-token\n")
            XCTAssertEqual(currentDirectoryURL, stateURL)
            XCTAssertTrue(arguments.contains("--device"))
            XCTAssertTrue(arguments.contains("--email"))
            XCTAssertTrue(arguments.contains("user@example.com"))
            XCTAssertTrue(arguments.contains("--token-stdin"))
            XCTAssertFalse(arguments.contains("master-token"))
            XCTAssertTrue(arguments.contains("--app"))
            XCTAssertTrue(arguments.contains("com.mojang.minecraftpe"))
            let output = """
            version code: 126200004
            version string: 1.26.20.4
            changelog: hello
            """
            return ProcessResult(status: 0, stdout: Data(output.utf8), stderr: Data())
        }
        let client = GPlayCLIClient(
            gplayverURL: gplayverURL,
            gplaydlURL: gplaydlURL,
            stateDirectoryURL: stateURL,
            processRunner: runner
        )

        let latest = try client.latest(
            credential: GoogleCredential(email: "user@example.com", masterToken: "master-token")
        )

        XCTAssertEqual(latest.versionName, "1.26.20.4")
        XCTAssertEqual(latest.versionCode, 126200004)
        XCTAssertFalse(latest.isBeta)
        let deviceConfig = try String(
            contentsOf: stateURL.appendingPathComponent("device.conf", isDirectory: false),
            encoding: .utf8
        )
        XCTAssertTrue(deviceConfig.contains("arm64-v8a"))
    }

    func testNotPurchasedGPlayverErrorBecomesOwnershipError() throws {
        let temp = try TemporaryDirectory()
        let gplayverURL = temp.url.appendingPathComponent("gplayver")
        let gplaydlURL = temp.url.appendingPathComponent("gplaydl")
        try writeExecutable(gplayverURL)
        try writeExecutable(gplaydlURL)
        let runner = MockProcessRunner { _, _, _, _, _ in
            ProcessResult(status: 1, stdout: Data(), stderr: Data("not purchased by user".utf8))
        }
        let client = GPlayCLIClient(
            gplayverURL: gplayverURL,
            gplaydlURL: gplaydlURL,
            stateDirectoryURL: temp.url.appendingPathComponent("state", isDirectory: true),
            processRunner: runner
        )

        XCTAssertThrowsError(
            try client.latest(credential: GoogleCredential(email: "user@example.com", masterToken: "master-token"))
        ) { error in
            guard case LauncherError.minecraftNotOwned(let account) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(account, "user@example.com")
        }
    }

    func testNotPurchasedGPlaydlStdoutErrorBecomesOwnershipError() throws {
        let temp = try TemporaryDirectory()
        let gplayverURL = temp.url.appendingPathComponent("gplayver")
        let gplaydlURL = temp.url.appendingPathComponent("gplaydl")
        try writeExecutable(gplayverURL)
        try writeExecutable(
            gplaydlURL,
            contents: """
            #!/bin/zsh
            print 'The item you were attempting to purchase could not be found'
            exit 11
            """
        )
        let client = GPlayCLIClient(
            gplayverURL: gplayverURL,
            gplaydlURL: gplaydlURL,
            stateDirectoryURL: temp.url.appendingPathComponent("state", isDirectory: true)
        )

        XCTAssertThrowsError(
            try client.download(
                versionCode: 123,
                outputDirectory: temp.url.appendingPathComponent("downloads", isDirectory: true),
                credential: GoogleCredential(email: "user@example.com", masterToken: "master-token")
            )
        ) { error in
            guard case LauncherError.minecraftNotOwned(let account) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(account, "user@example.com")
        }
    }

    func testGPlaydlStatusElevenWithoutOutputBecomesOwnershipError() throws {
        let temp = try TemporaryDirectory()
        let gplayverURL = temp.url.appendingPathComponent("gplayver")
        let gplaydlURL = temp.url.appendingPathComponent("gplaydl")
        try writeExecutable(gplayverURL)
        try writeExecutable(
            gplaydlURL,
            contents: """
            #!/bin/zsh
            exit 11
            """
        )
        let client = GPlayCLIClient(
            gplayverURL: gplayverURL,
            gplaydlURL: gplaydlURL,
            stateDirectoryURL: temp.url.appendingPathComponent("state", isDirectory: true)
        )

        XCTAssertThrowsError(
            try client.download(
                versionCode: 123,
                outputDirectory: temp.url.appendingPathComponent("downloads", isDirectory: true),
                credential: GoogleCredential(email: "user@example.com", masterToken: "master-token")
            )
        ) { error in
            guard case LauncherError.minecraftNotOwned(let account) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(account, "user@example.com")
        }
    }

    func testDownloadRunsGPlaydlAndCollectsBaseAndSplitAPKs() throws {
        let temp = try TemporaryDirectory()
        let gplayverURL = temp.url.appendingPathComponent("gplayver")
        let gplaydlURL = temp.url.appendingPathComponent("gplaydl")
        try writeExecutable(gplayverURL)
        try writeExecutable(
            gplaydlURL,
            contents: """
            #!/bin/zsh
            output=""
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == "--output" ]]; then
                output="$2"
                shift 2
              else
                shift
              fi
            done
            mkdir -p "${output:h}"
            printf '\\rDownloaded 25%% [3/12 MiB]'
            sleep 0.1
            printf '\\rDownloaded 100%% [12/12 MiB]'
            printf '\\rDownloaded 50%% [2/4 MiB]'
            sleep 0.1
            printf '\\rDownloaded 100%% [4/4 MiB]'
            print -n 'base' > "$output"
            split="${output:r}.config.arm64_v8a.apk"
            print -n 'split' > "$split"
            """
        )
        let downloadsURL = temp.url.appendingPathComponent("downloads", isDirectory: true)

        let client = GPlayCLIClient(
            gplayverURL: gplayverURL,
            gplaydlURL: gplaydlURL,
            stateDirectoryURL: temp.url.appendingPathComponent("state", isDirectory: true)
        )
        final class ProgressBox: @unchecked Sendable {
            private let lock = NSLock()
            private var events: [DownloadProgress] = []

            func append(_ event: DownloadProgress) {
                lock.lock()
                events.append(event)
                lock.unlock()
            }

            func snapshot() -> [DownloadProgress] {
                lock.lock()
                defer { lock.unlock() }
                return events
            }
        }
        let progressBox = ProgressBox()

        let response = try client.download(
            versionCode: 123,
            outputDirectory: downloadsURL,
            credential: GoogleCredential(email: "user@example.com", masterToken: "master-token")
        ) { progress in
            progressBox.append(progress)
        }

        XCTAssertEqual(response.packageName, "com.mojang.minecraftpe")
        XCTAssertEqual(response.versionCode, 123)
        XCTAssertEqual(response.files.map(\.component), ["base", "config.arm64_v8a"])
        let progressEvents = progressBox.snapshot()
        XCTAssertEqual(progressEvents.first?.bytesReceived, 3 * 1024 * 1024)
        XCTAssertEqual(progressEvents.last?.bytesReceived, 16 * 1024 * 1024)
        XCTAssertEqual(progressEvents.last?.totalBytes, 16 * 1024 * 1024)
        XCTAssertEqual(progressEvents.last?.fractionCompleted, 1)
    }
}
