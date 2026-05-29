import Foundation

public struct GooglePlayAuthRequest: Codable, Equatable, Sendable {
    public var accountIdentifier: String
    public var userID: String
    public var oauthToken: String

    public init(accountIdentifier: String, userID: String, oauthToken: String) {
        self.accountIdentifier = accountIdentifier
        self.userID = userID
        self.oauthToken = oauthToken
    }
}

public struct GooglePlayCredentialInput: Codable, Equatable, Sendable {
    public var email: String
    public var masterToken: String

    public init(email: String, masterToken: String) {
        self.email = email
        self.masterToken = masterToken
    }
}

public struct GooglePlayDownloadResponse: Codable, Equatable, Sendable {
    public var packageName: String
    public var versionCode: Int
    public var files: [DownloadedAPK]

    public init(packageName: String, versionCode: Int, files: [DownloadedAPK]) {
        self.packageName = packageName
        self.versionCode = versionCode
        self.files = files
    }
}

public protocol GooglePlayDownloading: Sendable {
    func auth(_ request: GooglePlayAuthRequest) async throws -> GoogleCredential

    func latest(
        packageName: String,
        abi: String,
        credential: GoogleCredential
    ) async throws -> LatestVersion

    func download(
        packageName: String,
        versionCode: Int,
        outputDirectory: URL,
        abi: String,
        credential: GoogleCredential,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> GooglePlayDownloadResponse

    func checkDownloadAccess(
        packageName: String,
        versionCode: Int,
        outputDirectory: URL,
        abi: String,
        credential: GoogleCredential
    ) async throws
}

public extension GooglePlayDownloading {
    func checkDownloadAccess(
        packageName: String,
        versionCode: Int,
        outputDirectory: URL,
        abi: String,
        credential: GoogleCredential
    ) async throws {
        _ = try await download(
            packageName: packageName,
            versionCode: versionCode,
            outputDirectory: outputDirectory,
            abi: abi,
            credential: credential,
            progress: { _ in }
        )
    }
}
