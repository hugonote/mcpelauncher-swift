import Foundation

public struct InstalledVersion: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { versionName }

    public var versionName: String
    public var versionCode: Int
    public var installPath: URL
    public var installedAt: Date

    public init(versionName: String, versionCode: Int, installPath: URL, installedAt: Date = Date()) {
        self.versionName = versionName
        self.versionCode = versionCode
        self.installPath = installPath
        self.installedAt = installedAt
    }
}

public enum DownloadPhase: String, Codable, Equatable, Sendable {
    case idle
    case authenticating
    case fetchingLatest
    case downloading
    case extracting
    case installed
    case failed
}

public struct DownloadState: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var versionName: String?
    public var progress: Double
    public var phase: DownloadPhase
    public var error: String?
    public var detail: String?
    public var bytesReceived: Int64?
    public var totalBytes: Int64?
    public var speedBytesPerSecond: Double?
    public var etaSeconds: Double?

    public init(
        id: UUID = UUID(),
        versionName: String? = nil,
        progress: Double = 0,
        phase: DownloadPhase = .idle,
        error: String? = nil,
        detail: String? = nil,
        bytesReceived: Int64? = nil,
        totalBytes: Int64? = nil,
        speedBytesPerSecond: Double? = nil,
        etaSeconds: Double? = nil
    ) {
        self.id = id
        self.versionName = versionName
        self.progress = progress
        self.phase = phase
        self.error = error
        self.detail = detail
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
    }
}

public struct DownloadProgress: Codable, Equatable, Sendable {
    public var bytesReceived: Int64
    public var totalBytes: Int64?
    public var speedBytesPerSecond: Double?
    public var etaSeconds: Double?
    public var component: String?
    public var componentIndex: Int?
    public var componentCount: Int?

    public init(
        bytesReceived: Int64,
        totalBytes: Int64? = nil,
        speedBytesPerSecond: Double? = nil,
        etaSeconds: Double? = nil,
        component: String? = nil,
        componentIndex: Int? = nil,
        componentCount: Int? = nil
    ) {
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.component = component
        self.componentIndex = componentIndex
        self.componentCount = componentCount
    }

    public var fractionCompleted: Double {
        guard let totalBytes, totalBytes > 0 else {
            return 0
        }
        return min(max(Double(bytesReceived) / Double(totalBytes), 0), 1)
    }
}

public enum RuntimePhase: String, Codable, Equatable, Sendable {
    case missing
    case checking
    case downloading
    case installing
    case ready
    case failed
}

public struct RuntimeState: Codable, Equatable, Sendable {
    public var phase: RuntimePhase
    public var version: String?
    public var detail: String?
    public var error: String?
    public var progress: Double
    public var bytesReceived: Int64?
    public var totalBytes: Int64?
    public var speedBytesPerSecond: Double?
    public var etaSeconds: Double?

    public init(
        phase: RuntimePhase = .missing,
        version: String? = nil,
        detail: String? = nil,
        error: String? = nil,
        progress: Double = 0,
        bytesReceived: Int64? = nil,
        totalBytes: Int64? = nil,
        speedBytesPerSecond: Double? = nil,
        etaSeconds: Double? = nil
    ) {
        self.phase = phase
        self.version = version
        self.detail = detail
        self.error = error
        self.progress = progress
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
    }
}

public struct RuntimeRelease: Codable, Equatable, Sendable {
    public var version: String
    public var assetName: String
    public var downloadURL: URL
    public var sha256: String?
    public var size: Int64?

    public init(version: String, assetName: String, downloadURL: URL, sha256: String? = nil, size: Int64? = nil) {
        self.version = version
        self.assetName = assetName
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.size = size
    }
}

public struct RuntimeMetadata: Codable, Equatable, Sendable {
    public var version: String
    public var assetName: String
    public var sourceURL: URL
    public var installedAt: Date

    public init(version: String, assetName: String, sourceURL: URL, installedAt: Date = Date()) {
        self.version = version
        self.assetName = assetName
        self.sourceURL = sourceURL
        self.installedAt = installedAt
    }
}

public struct GoogleCredential: Codable, Equatable, Sendable {
    public var email: String
    public var masterToken: String
    public var userID: String?

    public init(email: String, masterToken: String, userID: String? = nil) {
        self.email = email
        self.masterToken = masterToken
        self.userID = userID
    }
}

public struct LatestVersion: Codable, Equatable, Sendable {
    public var packageName: String
    public var versionName: String
    public var versionCode: Int
    public var isBeta: Bool

    public init(packageName: String, versionName: String, versionCode: Int, isBeta: Bool) {
        self.packageName = packageName
        self.versionName = versionName
        self.versionCode = versionCode
        self.isBeta = isBeta
    }
}

public struct SupportedMinecraftVersion: Codable, Equatable, Hashable, Sendable {
    public var versionName: String
    public var versionCode: Int

    public init(versionName: String, versionCode: Int) {
        self.versionName = versionName
        self.versionCode = versionCode
    }
}

public struct CompatibilityPatchMetadata: Codable, Equatable, Sendable {
    public var version: String
    public var assetURL: URL
    public var installPath: URL
    public var supportedVersions: [SupportedMinecraftVersion]
    public var installedAt: Date

    public init(
        version: String,
        assetURL: URL,
        installPath: URL,
        supportedVersions: [SupportedMinecraftVersion],
        installedAt: Date = Date()
    ) {
        self.version = version
        self.assetURL = assetURL
        self.installPath = installPath
        self.supportedVersions = supportedVersions
        self.installedAt = installedAt
    }

    public var newestSupportedVersion: SupportedMinecraftVersion? {
        supportedVersions.max { $0.versionCode < $1.versionCode }
    }

    public func supports(versionCode: Int) -> Bool {
        supportedVersions.contains { $0.versionCode == versionCode }
    }
}

public struct DownloadedAPK: Codable, Equatable, Sendable {
    public var component: String
    public var path: URL
    public var size: Int64?

    public init(component: String, path: URL, size: Int64? = nil) {
        self.component = component
        self.path = path
        self.size = size
    }

    private enum CodingKeys: String, CodingKey {
        case component
        case path
        case size
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        component = try container.decode(String.self, forKey: .component)
        let rawPath = try container.decode(String.self, forKey: .path)
        if rawPath.hasPrefix("file://"), let url = URL(string: rawPath) {
            path = url
        } else {
            path = URL(fileURLWithPath: rawPath)
        }
        size = try container.decodeIfPresent(Int64.self, forKey: .size)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(component, forKey: .component)
        try container.encode(path.isFileURL ? path.path : path.absoluteString, forKey: .path)
        try container.encodeIfPresent(size, forKey: .size)
    }
}
