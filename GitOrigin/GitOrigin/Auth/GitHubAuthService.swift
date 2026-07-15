//
//  GitHubAuthService.swift
//  GitOrigin
//
//  Observable sign-in state for the app gate. Owns the OAuth device flow, persisted token,
//  and pushes the access token into GitExecutor for HTTPS remotes.
//

import AppKit
import Foundation
import Observation

struct GitHubSession: Equatable, Sendable {
    let login: String
    let avatarURL: URL?
}

enum GitHubAuthError: LocalizedError, Equatable {
    case signInCancelled
    case networkFailure(String)

    var errorDescription: String? {
        switch self {
        case .signInCancelled:
            "GitHub sign-in was cancelled."
        case .networkFailure(let message):
            message
        }
    }
}

@Observable
@MainActor
final class GitHubAuthService {
    /// Signed-in GitHub user, or nil before sign-in / after sign-out.
    private(set) var session: GitHubSession?
    private(set) var isSigningIn = false
    private(set) var isRestoringSession = true
    private(set) var pendingDeviceAuthorization: GitHubDeviceAuthorization?
    private(set) var lastError: GitHubAuthError?

    var isSignedIn: Bool { session != nil }

    /// Used as GIT_AUTHOR_* / GIT_COMMITTER_* when creating commits.
    var commitAuthor: (name: String, email: String)? {
        guard let login = session?.login else { return nil }
        return (login, "\(login)@users.noreply.github.com")
    }

    private let oauth = GitHubOAuthClient.shared
    private var signInTask: Task<Void, Never>?

    func restoreSessionIfAvailable() async {
        defer { isRestoringSession = false }
        lastError = nil

        guard session == nil else { return }

        do {
            guard let token = GitHubKeychain.loadAccessToken() else { return }
            let user = try await oauth.fetchCurrentUser(accessToken: token)
            session = GitHubSession(login: user.login, avatarURL: user.avatarURL)
            await GitExecutor.shared.setGitHubAccessToken(token)
        } catch {
            GitHubKeychain.deleteAccessToken()
            session = nil
            await GitExecutor.shared.setGitHubAccessToken(nil)
        }
    }

    func signIn() async {
        signInTask?.cancel()
        await signInTask?.value

        lastError = nil
        pendingDeviceAuthorization = nil
        isSigningIn = true

        signInTask = Task {
            defer {
                isSigningIn = false
                pendingDeviceAuthorization = nil
            }

            do {
                let authorization = try await oauth.requestDeviceAuthorization()
                pendingDeviceAuthorization = authorization
                openDeviceVerificationInBrowser(authorization)

                let token = try await oauth.pollAccessToken(
                    deviceCode: authorization.deviceCode,
                    interval: authorization.pollingInterval
                )

                GitHubKeychain.saveAccessToken(token)

                let user = try await oauth.fetchCurrentUser(accessToken: token)
                session = GitHubSession(login: user.login, avatarURL: user.avatarURL)
                await GitExecutor.shared.setGitHubAccessToken(token)
            } catch is CancellationError {
                lastError = .signInCancelled
            } catch let error as GitHubOAuthClientError {
                lastError = .networkFailure(error.localizedDescription ?? "GitHub sign-in failed.")
            } catch {
                lastError = .networkFailure(error.localizedDescription)
            }
        }

        await signInTask?.value
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        pendingDeviceAuthorization = nil
        isSigningIn = false
    }

    func signOut() {
        cancelSignIn()
        session = nil
        lastError = nil

        GitHubKeychain.deleteAccessToken()
        Task { await GitExecutor.shared.setGitHubAccessToken(nil) }
    }

    func clearLastError() {
        lastError = nil
    }

    func openDeviceVerificationInBrowser(_ authorization: GitHubDeviceAuthorization? = nil) {
        let auth = authorization ?? pendingDeviceAuthorization
        guard let auth else { return }

        var components = URLComponents(url: auth.verificationURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "user_code", value: auth.userCode))
        components?.queryItems = queryItems

        if let url = components?.url {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(auth.verificationURL)
        }
    }
}

#if DEBUG
extension GitHubAuthService {
    static var previewSignedIn: GitHubAuthService {
        let service = GitHubAuthService()
        service.isRestoringSession = false
        service.session = GitHubSession(login: "octocat", avatarURL: nil)
        return service
    }
}
#endif
