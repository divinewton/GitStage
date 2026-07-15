//
//  GitHubAuthConfiguration.swift
//  GitStage
//

import Foundation

/// GitHub OAuth settings for the device authorization flow.
///
/// The **client ID is safe to ship in the app** — it is public in every OAuth desktop/mobile client.
/// Never embed a **client secret** in GitStage; device flow does not use one.
enum GitHubAuthConfiguration {
    static var clientID: String { GitHubAuthSecrets.clientID }

    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    static let userAPIURL = URL(string: "https://api.github.com/user")!

    /// Scopes required for fetch/pull/push over HTTPS.
    static let defaultScopes = ["repo", "read:user"]
}
