import Foundation
import Security

public protocol CredentialStore: Sendable {
    func loadCredential() throws -> GoogleCredential?
    func saveCredential(_ credential: GoogleCredential) throws
    func clearCredential() throws
}

public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        service: String = "local.minecraft.bedrock.swift-launcher",
        account: String = "google-play"
    ) {
        self.service = service
        self.account = account
    }

    public func loadCredential() throws -> GoogleCredential? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw KeychainError.accessDenied
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }
        return try decoder.decode(GoogleCredential.self, from: data)
    }

    public func saveCredential(_ credential: GoogleCredential) throws {
        let data = try encoder.encode(credential)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrLabel as String] = "Google Play token"
        query[kSecAttrDescription as String] = "Google Play token for Minecraft Bedrock Launcher"
        query[kSecAttrComment as String] = "Used to check Minecraft Bedrock updates and pass Google Play credentials to the game launcher."
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        guard addStatus == errSecDuplicateItem else {
            throw KeychainError.unhandledStatus(addStatus)
        }

        let deleteStatus = SecItemDelete(baseQuery() as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(deleteStatus)
        }
        let retryStatus = SecItemAdd(query as CFDictionary, nil)
        guard retryStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(retryStatus)
        }
    }

    public func clearCredential() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum KeychainError: Error, LocalizedError, Equatable {
    case accessDenied
    case unhandledStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Keychain access was denied."
        case .unhandledStatus(let status):
            return "Keychain operation failed with status \(status)."
        case .invalidData:
            return "Keychain item did not contain credential data."
        }
    }
}

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: GoogleCredential?

    public init(credential: GoogleCredential? = nil) {
        self.credential = credential
    }

    public func loadCredential() throws -> GoogleCredential? {
        lock.lock()
        defer { lock.unlock() }
        return credential
    }

    public func saveCredential(_ credential: GoogleCredential) throws {
        lock.lock()
        defer { lock.unlock() }
        self.credential = credential
    }

    public func clearCredential() throws {
        lock.lock()
        defer { lock.unlock() }
        credential = nil
    }
}
