import Foundation
import Security

struct ClaudeCredential: Equatable, Sendable {
    let accessToken: String
    let expiresAtMilliseconds: Int?
    let rateLimitTier: String?
    let subscriptionType: String?

    func isExpired(at date: Date = .now) -> Bool {
        guard let expiresAtMilliseconds else { return false }
        return expiresAtMilliseconds <= Int(date.timeIntervalSince1970 * 1_000)
    }
}

struct ClaudeCredentialLoader: Sendable {
    private static let keychainService = "Claude Code-credentials"
    private let keychainData: @Sendable () -> Data?

    init(keychainData: @escaping @Sendable () -> Data? = ClaudeCredentialLoader.readKeychain) {
        self.keychainData = keychainData
    }

    /// Keychain is Claude Code's primary macOS store; a leftover credential file can be stale, so
    /// both sources are read and the credential that stays valid the longest wins.
    func load(fileURL: URL) -> ClaudeCredential? {
        let candidates = [keychainData().flatMap(decode), (try? Data(contentsOf: fileURL)).flatMap(decode)].compactMap { $0 }
        return candidates.max { ($0.expiresAtMilliseconds ?? .max) < ($1.expiresAtMilliseconds ?? .max) }
    }

    func decode(_ data: Data) -> ClaudeCredential? {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data),
              let login = root["claudeAiOauth"],
              let accessToken = login["accessToken"]?.string,
              !accessToken.isEmpty else { return nil }
        return ClaudeCredential(
            accessToken: accessToken,
            expiresAtMilliseconds: login["expiresAt"]?.number.map(Int.init),
            rateLimitTier: login["rateLimitTier"]?.string,
            subscriptionType: login["subscriptionType"]?.string
        )
    }

    @Sendable static func readKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}
