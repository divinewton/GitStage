//
//  GitHubKeychain.swift
//  GitOrigin
//
//  Persists the GitHub OAuth access token between launches in UserDefaults.
//

import Foundation

enum GitHubKeychain {
    private static let tokenKey = "github-oauth-access-token"

    static func saveAccessToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    static func loadAccessToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static func deleteAccessToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
