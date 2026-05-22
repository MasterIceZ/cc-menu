import Foundation
import Security

struct KeychainCredentials {
    let accessToken: String
    let refreshToken: String?
}

func readKeychainCredentials() -> KeychainCredentials? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let accessToken = oauth["accessToken"] as? String
    else { return nil }

    return KeychainCredentials(
        accessToken: accessToken,
        refreshToken: oauth["refreshToken"] as? String
    )
}
