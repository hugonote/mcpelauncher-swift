import Foundation
import FinskyKit

public struct FinskyGooglePlayClient: GooglePlayDownloading, Sendable {
    private let client: any FinskyDownloading

    public init() {
        self.client = FinskyClient()
    }

    init(client: any FinskyDownloading) {
        self.client = client
    }

    public func auth(_ request: GooglePlayAuthRequest) async throws -> GoogleCredential {
        do {
            let credential = try await client.auth(
                accessToken: request.oauthToken,
                fallbackEmail: request.accountIdentifier.isEmpty ? nil : request.accountIdentifier,
                userID: request.userID
            )
            guard let email = credential.email, !email.isEmpty else {
                throw LauncherError.googlePlayCredentialRequiresSignIn
            }
            return GoogleCredential(
                email: email,
                masterToken: credential.masterToken,
                userID: credential.userID,
                finskyCredential: credential
            )
        } catch let error as LauncherError {
            throw error
        } catch let error as FinskyError {
            throw mapFinskyError(error, account: request.accountIdentifier)
        }
    }

    public func latest(
        packageName: String = "com.mojang.minecraftpe",
        abi: String = "arm64-v8a",
        credential: GoogleCredential
    ) async throws -> LatestVersion {
        do {
            let finskyCredential = try makeFinskyCredential(from: credential)
            let version = try await client.latest(
                packageName: packageName,
                abi: abi,
                credential: finskyCredential
            )
            return LatestVersion(
                packageName: version.packageName,
                versionName: version.versionName ?? String(version.versionCode),
                versionCode: version.versionCode,
                isBeta: false
            )
        } catch let error as LauncherError {
            throw error
        } catch let error as FinskyError {
            throw mapFinskyError(error, account: credential.email)
        }
    }

    public func download(
        packageName: String = "com.mojang.minecraftpe",
        versionCode: Int,
        outputDirectory: URL,
        abi: String = "arm64-v8a",
        credential: GoogleCredential,
        progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }
    ) async throws -> GooglePlayDownloadResponse {
        do {
            let finskyCredential = try makeFinskyCredential(from: credential)
            let apks = try await client.download(
                packageName: packageName,
                versionCode: versionCode,
                abi: abi,
                credential: finskyCredential,
                outputDirectory: outputDirectory
            ) { event in
                progress(downloadProgress(from: event))
            }
            let downloaded = apks.map { apk in
                DownloadedAPK(
                    component: componentName(for: apk),
                    path: apk.fileURL,
                    size: apk.sizeBytes
                )
            }
            return GooglePlayDownloadResponse(
                packageName: packageName,
                versionCode: versionCode,
                files: downloaded
            )
        } catch let error as LauncherError {
            throw error
        } catch let error as FinskyError {
            throw mapFinskyError(error, account: credential.email)
        }
    }

    public func checkDownloadAccess(
        packageName: String = "com.mojang.minecraftpe",
        versionCode: Int,
        outputDirectory: URL,
        abi: String = "arm64-v8a",
        credential: GoogleCredential
    ) async throws {
        do {
            let finskyCredential = try makeFinskyCredential(from: credential)
            try await client.checkDownloadAccess(
                packageName: packageName,
                versionCode: versionCode,
                abi: abi,
                credential: finskyCredential
            )
        } catch let error as LauncherError {
            throw error
        } catch let error as FinskyError {
            throw mapFinskyError(error, account: credential.email)
        }
    }

    private func makeFinskyCredential(from credential: GoogleCredential) throws -> FinskyCredential {
        guard let finskyCredential = credential.finskyCredential else {
            throw LauncherError.googlePlayCredentialRequiresSignIn
        }
        return finskyCredential
    }

    private func mapFinskyError(_ error: FinskyError, account: String?) -> LauncherError {
        switch error {
        case .notOwned, .notPurchased, .noEntitlement:
            return .minecraftNotOwned(account: account)
        case .httpStatus(let code, _) where code == 401:
            return .googlePlayCredentialRequiresSignIn
        case .invalidAuthResponse:
            return .googlePlayCredentialRequiresSignIn
        default:
            return .googlePlayFailed(error.localizedDescription)
        }
    }

    private func downloadProgress(from event: FinskyDownloadProgress) -> DownloadProgress {
        DownloadProgress(
            bytesReceived: event.totalBytesReceived,
            totalBytes: event.totalBytesExpected,
            speedBytesPerSecond: event.speedBytesPerSecond,
            etaSeconds: event.etaSeconds,
            component: event.fileName,
            componentIndex: currentComponentIndex(for: event),
            componentCount: event.totalFiles
        )
    }

    private func currentComponentIndex(for event: FinskyDownloadProgress) -> Int? {
        guard event.totalFiles > 0 else {
            return nil
        }
        return min(event.completedFiles + 1, event.totalFiles)
    }

    private func componentName(for apk: FinskyAPK) -> String {
        switch apk.kind {
        case .base:
            return "base"
        case .split:
            return apk.splitName?.isEmpty == false ? apk.splitName! : "split"
        }
    }
}
