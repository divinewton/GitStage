//
//  GitHubKeychain.swift
//  GitOrigin
//
//  Persists the GitHub OAuth access token between launches.
//  Uses UserDefaults so sandboxed builds do not trigger the macOS login-keychain password dialog.
//

import Foundation
import Security

enum GitHubKeychain {
    private static let tokenKey = "github-oauth-access-token"

    static func saveAccessToken(_ token: String) throws {
        UserDefaults.standard.set(token, forKey: tokenKey)
        deleteLegacyKeychainItemIfPresent()
    }

    static func loadAccessToken() throws -> String? {
        deleteLegacyKeychainItemIfPresent()
        return UserDefaults.standard.string(forKey: tokenKey)
    }

    static func deleteAccessToken() throws {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        deleteLegacyKeychainItemIfPresent()
    }

    /// Removes tokens saved by older builds that used the Keychain directly.
    private static func deleteLegacyKeychainItemIfPresent() {
        for service in legacyKeychainServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "github-access-token",
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    private static let legacyKeychainServices = [
        "com.divinewton.GitOrigin",
        "divinewton.GitOrigin",
        "GitOrigin",
    ]
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Could not save sign-in credentials (\(status))."
        case .invalidData:
            "Stored sign-in credentials were invalid."
        }
    }
}
