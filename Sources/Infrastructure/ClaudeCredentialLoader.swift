import Foundation
import Security

struct ClaudeCredential: Equatable, Sendable {
    let accessToken: String
    let expiresAtMilliseconds: Int?
    let rateLimitTier: String?
    let subscriptionType: String?
}

struct ClaudeCredentialLoader: Sendable {
    private static let keychainService = "Claude Code-credentials"

    func load(fileURL: URL) -> ClaudeCredential? {
        if let data = try? Data(contentsOf: fileURL), let credential = decode(data) {
            return credential
        }
        return keychainData().flatMap(decode)
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

    private func keychainData() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}
