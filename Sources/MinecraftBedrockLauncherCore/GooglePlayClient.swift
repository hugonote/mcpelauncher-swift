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
