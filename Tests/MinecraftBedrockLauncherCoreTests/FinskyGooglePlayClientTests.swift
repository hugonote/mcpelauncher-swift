import Foundation
import FinskyKit
import XCTest
@testable import MinecraftBedrockLauncherCore

final class FinskyGooglePlayClientTests: XCTestCase {
    func testAuthMapsFinskyCredentialToGoogleCredential() async throws {
        let fake = FakeFinskyClient()
        let authResult = try FinskyCredentialFixture.credential()
        fake.authResult = authResult
        let client = makeClient(fake)

        let credential = try await client.auth(GooglePlayAuthRequest(
            accountIdentifier: "fallback@example.com",
            userID: "user-id",
            oauthToken: "access-token"
        ))

        XCTAssertEqual(credential.email, "user@example.com")
        XCTAssertEqual(credential.masterToken, "master-token")
        XCTAssertEqual(credential.userID, "user-id")
        XCTAssertEqual(credential.finskyCredential, authResult)
    }

    func testLatestRequiresNativeCredentialStateForLegacyCredential() async throws {
        let client = makeClient(FakeFinskyClient())

        do {
            _ = try await client.latest(credential: GoogleCredential(email: "user@example.com", masterToken: "master-token"))
            XCTFail("Expected googlePlayCredentialRequiresSignIn to be thrown.")
        } catch LauncherError.googlePlayCredentialRequiresSignIn {
            // expected
        }
    }

    func testLatestMapsFinskyVersion() async throws {
        let fake = FakeFinskyClient()
        fake.latestResult = FinskyVersion(
            packageName: "com.mojang.minecraftpe",
            versionCode: 840626000,
            versionName: "1.20.81.01",
            abi: "arm64-v8a"
        )
        let client = makeClient(fake)

        let latest = try await client.latest(credential: FinskyCredentialFixture.googleCredential())

        XCTAssertEqual(latest.packageName, "com.mojang.minecraftpe")
        XCTAssertEqual(latest.versionCode, 840626000)
        XCTAssertEqual(latest.versionName, "1.20.81.01")
        XCTAssertFalse(latest.isBeta)
    }

    func testDownloadMapsProgressAndFiles() async throws {
        let temp = try TemporaryDirectory()
        let apkURL = temp.url.appendingPathComponent("base.apk")
        let fake = FakeFinskyClient()
        fake.downloadResult = [
            FinskyAPK(
                kind: .base,
                splitName: nil,
                fileName: "base.apk",
                fileURL: apkURL,
                sizeBytes: 4
            )
        ]
        let client = makeClient(fake)
        let progressRecorder = ProgressRecorder()

        let response = try await client.download(
            versionCode: 840626000,
            outputDirectory: temp.url,
            credential: FinskyCredentialFixture.googleCredential()
        ) { progress in
            progressRecorder.append(progress)
        }

        XCTAssertEqual(response.files, [
            DownloadedAPK(component: "base", path: apkURL, size: 4)
        ])
        XCTAssertEqual(progressRecorder.last?.bytesReceived, 4)
        XCTAssertEqual(progressRecorder.last?.totalBytes, 4)
        XCTAssertEqual(progressRecorder.last?.speedBytesPerSecond, 2048)
        XCTAssertEqual(progressRecorder.last?.etaSeconds, 3)
    }

    private func makeClient(_ fake: FakeFinskyClient) -> FinskyGooglePlayClient {
        FinskyGooglePlayClient(client: fake)
    }
}

private final class FakeFinskyClient: FinskyDownloading, @unchecked Sendable {
    var authResult: FinskyCredential?
    var latestResult: FinskyVersion?
    var latestCredential: FinskyCredential?
    var downloadResult: [FinskyAPK]?

    func auth(
        accessToken: String,
        fallbackEmail: String?,
        userID: String
    ) async throws -> FinskyCredential {
        guard let authResult else {
            throw FakeFinskyClientError.missingAuthResult
        }
        return authResult
    }

    func importLegacyCredential(
        email: String,
        userID: String,
        masterToken: String
    ) async throws -> FinskyCredential {
        guard let authResult else {
            throw FakeFinskyClientError.missingAuthResult
        }
        return authResult
    }

    func latest(
        packageName: String,
        abi: String,
        credential: FinskyCredential
    ) async throws -> FinskyVersion {
        latestCredential = credential
        guard let latestResult else {
            throw FakeFinskyClientError.missingLatestResult
        }
        return latestResult
    }

    func download(
        packageName: String,
        versionCode: Int,
        abi: String,
        credential: FinskyCredential,
        outputDirectory: URL,
        progress: @Sendable @escaping (FinskyDownloadProgress) -> Void
    ) async throws -> [FinskyAPK] {
        progress(FinskyDownloadProgress(
            packageName: packageName,
            fileName: "base.apk",
            bytesReceived: 4,
            totalBytesReceived: 4,
            totalBytesExpected: 4,
            completedFiles: 1,
            totalFiles: 1,
            speedBytesPerSecond: 2048,
            etaSeconds: 3
        ))
        guard let downloadResult else {
            throw FakeFinskyClientError.missingDownloadResult
        }
        return downloadResult
    }

    func checkDownloadAccess(
        packageName: String,
        versionCode: Int,
        abi: String,
        credential: FinskyCredential
    ) async throws {}
}

private enum FakeFinskyClientError: Error {
    case missingAuthResult
    case missingLatestResult
    case missingDownloadResult
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [DownloadProgress] = []

    var last: DownloadProgress? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }

    func append(_ progress: DownloadProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }
}
