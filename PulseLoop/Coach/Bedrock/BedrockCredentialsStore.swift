import Foundation
import Security

/// Securely stores the AWS credentials used for the Bedrock coach provider.
///
/// The **secret access key** is a credential and must never live in source or
/// UserDefaults, so all three values (access key id, secret, session token) are
/// kept in the Keychain. Region and model id are *not* secret and live in
/// `CoachSettings` (so they sync with the rest of the coach config and show in
/// the Settings UI).
struct BedrockCredentials: Equatable, Sendable {
    var accessKeyID: String
    var secretAccessKey: String
    /// Optional STS session token (temporary credentials). Empty for IAM user keys.
    var sessionToken: String

    var isComplete: Bool {
        !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Keychain-backed store for `BedrockCredentials`. Mirrors `OpenAIKeychainStore`
/// (generic password), but stores a small JSON blob because Bedrock needs more
/// than a single token.
struct BedrockCredentialsStore {
    private let service: String
    private let account: String

    init(service: String = "com.pulseloop.coach.bedrock", account: String = "bedrock_credentials") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> BedrockCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let decoded = try? JSONDecoder().decode(StoredBlob.self, from: data) else { return nil }
        return BedrockCredentials(
            accessKeyID: decoded.accessKeyID,
            secretAccessKey: decoded.secretAccessKey,
            sessionToken: decoded.sessionToken ?? ""
        )
    }

    func save(_ credentials: BedrockCredentials) throws {
        let blob = StoredBlob(
            accessKeyID: credentials.accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: credentials.secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionToken: credentials.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard let data = try? JSONEncoder().encode(blob) else { throw KeychainError.dataEncoding }

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
            return
        }
        throw KeychainError.unexpectedStatus(updateStatus)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    var hasCredentials: Bool { read()?.isComplete ?? false }

    private struct StoredBlob: Codable {
        let accessKeyID: String
        let secretAccessKey: String
        var sessionToken: String?
    }
}
