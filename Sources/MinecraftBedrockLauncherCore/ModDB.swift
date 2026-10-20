import Foundation

public struct ModDBClient: Sendable {
    public static let defaultURL = URL(string: "https://raw.githubusercontent.com/minecraft-linux/mcpelauncher-moddb/main/moddb.json")!

    private let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public func fetchEntries() async throws -> [ModDBEntry] {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LauncherError.runtimeInstallFailed("Mod catalog lookup returned HTTP \(http.statusCode).")
        }
        return try JSONDecoder().decode([ModDBEntry].self, from: data)
    }
}

public struct ModDBEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }

    public var name: String
    public var description: String
    public var url: String
    public var image: String
    public var versions: [ModDBVersion]

    public init(name: String, description: String, url: String, image: String, versions: [ModDBVersion]) {
        self.name = name
        self.description = description
        self.url = url
        self.image = image
        self.versions = versions
    }

    public func newestVersion(for abi: String) -> ModDBVersion? {
        versions.last { $0.assetURL(for: abi) != nil }
    }
}

public struct ModDBVersion: Codable, Equatable, Hashable, Sendable {
    public var version: String
    public var assets: [String: String]
    public var minecraft: String?
    public var extraVersions: [ModDBExtraVersion]
    public var provides: [String: ModDBProvidedVersions]

    public var compatibleExtraVersions: [ModDBExtraVersion] {
        extraVersions + provides.values.flatMap(\.extraVersions)
    }

    enum CodingKeys: String, CodingKey {
        case version
        case assets
        case minecraft
        case extraVersions
        case provides
    }

    public init(
        version: String,
        assets: [String: String],
        minecraft: String? = nil,
        extraVersions: [ModDBExtraVersion] = [],
        provides: [String: ModDBProvidedVersions] = [:]
    ) {
        self.version = version
        self.assets = assets
        self.minecraft = minecraft
        self.extraVersions = extraVersions
        self.provides = provides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        assets = try container.decodeIfPresent([String: String].self, forKey: .assets) ?? [:]
        minecraft = try container.decodeIfPresent(String.self, forKey: .minecraft)
        extraVersions = try container.decodeIfPresent([ModDBExtraVersion].self, forKey: .extraVersions) ?? []
        provides = try container.decodeIfPresent([String: ModDBProvidedVersions].self, forKey: .provides) ?? [:]
    }

    public func assetURL(for abi: String) -> URL? {
        assets[abi].flatMap(URL.init(string:))
    }
}

public struct ModDBProvidedVersions: Codable, Equatable, Hashable, Sendable {
    public var extraVersions: [ModDBExtraVersion]

    public init(extraVersions: [ModDBExtraVersion]) {
        self.extraVersions = extraVersions
    }
}

public struct ModDBExtraVersion: Codable, Equatable, Hashable, Sendable {
    public var versionName: String
    public var codes: [String: Int]

    enum CodingKeys: String, CodingKey {
        case versionName = "version_name"
        case codes
    }

    public init(versionName: String, codes: [String: Int]) {
        self.versionName = versionName
        self.codes = codes
    }
}

public struct MinecraftVersionRequirement: Equatable, Sendable {
    private enum Comparison: String, CaseIterable {
        case greaterOrEqual = ">="
        case lessOrEqual = "<="
        case equal = "=="
        case greater = ">"
        case less = "<"
    }

    private let comparison: Comparison
    private let version: [Int]

    public init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        let comparison = Comparison.allCases.first { trimmed.hasPrefix($0.rawValue) } ?? .equal
        let versionText = trimmed.hasPrefix(comparison.rawValue)
            ? String(trimmed.dropFirst(comparison.rawValue.count))
            : trimmed
        guard let version = Self.components(of: versionText) else {
            return nil
        }
        self.comparison = comparison
        self.version = version
    }

    public func isSatisfied(by versionName: String) -> Bool {
        guard let candidate = Self.components(of: versionName) else {
            return true
        }
        let order = Self.compare(candidate, version)
        switch comparison {
        case .greaterOrEqual:
            return order != .orderedAscending
        case .lessOrEqual:
            return order != .orderedDescending
        case .equal:
            return order == .orderedSame
        case .greater:
            return order == .orderedDescending
        case .less:
            return order == .orderedAscending
        }
    }

    private static func components(of text: String) -> [Int]? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".")
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count else {
            return nil
        }
        return numbers
    }

    private static func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left < right ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }
}
