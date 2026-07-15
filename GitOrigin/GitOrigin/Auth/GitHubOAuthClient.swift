//
//  GitHubOAuthClient.swift
//  GitOrigin
//
//  Low-level GitHub HTTP client: OAuth device flow, user profile, repository list, and PRs.
//

import Foundation

struct GitHubDeviceAuthorization: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: TimeInterval
    let pollingInterval: TimeInterval
}

struct GitHubAuthenticatedUser: Sendable {
    let login: String
    let avatarURL: URL?
}

struct GitHubRemoteRepository: Sendable, Equatable {
    let owner: String
    let fullName: String
    let name: String
    let htmlURL: URL
    let cloneURL: URL
    let defaultBranch: String
}

enum GitHubOAuthClientError: LocalizedError {
    case invalidResponse
    case httpFailure(Int, String)
    case oauthFailure(String)
    case authorizationPending
    case slowDown
    case expiredToken
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned an unexpected response."
        case .httpFailure(let code, let message):
            "GitHub request failed (\(code)): \(message)"
        case .oauthFailure(let message):
            message
        case .authorizationPending:
            "Waiting for GitHub authorization."
        case .slowDown:
            "GitHub asked to slow down polling."
        case .expiredToken:
            "The sign-in code expired. Try again."
        case .accessDenied:
            "GitHub sign-in was denied or cancelled."
        }
    }
}

actor GitHubOAuthClient {
    static let shared = GitHubOAuthClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func requestDeviceAuthorization() async throws -> GitHubDeviceAuthorization {
        let body = formBody([
            "client_id": GitHubAuthConfiguration.clientID,
            "scope": GitHubAuthConfiguration.defaultScopes.joined(separator: " "),
        ])

        let data = try await post(
            to: GitHubAuthConfiguration.deviceCodeURL,
            body: body,
            acceptJSON: true
        )

        let response = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        guard let verificationURL = URL(string: response.verificationURI) else {
            throw GitHubOAuthClientError.invalidResponse
        }

        return GitHubDeviceAuthorization(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURL: verificationURL,
            expiresIn: TimeInterval(response.expiresIn),
            pollingInterval: TimeInterval(max(response.interval, 5))
        )
    }

    func pollAccessToken(deviceCode: String, interval: TimeInterval) async throws -> String {
        let body = formBody([
            "client_id": GitHubAuthConfiguration.clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])

        var wait = interval

        while true {
            try Task.checkCancellation()

            let data = try await post(
                to: GitHubAuthConfiguration.accessTokenURL,
                body: body,
                acceptJSON: true
            )

            let response = try JSONDecoder().decode(AccessTokenResponse.self, from: data)

            if let token = response.accessToken, !token.isEmpty {
                return token
            }

            switch response.error {
            case "authorization_pending":
                try await Task.sleep(for: .seconds(wait))
                continue
            case "slow_down":
                wait += 5
                try await Task.sleep(for: .seconds(wait))
                continue
            case "expired_token":
                throw GitHubOAuthClientError.expiredToken
            case "access_denied":
                throw GitHubOAuthClientError.accessDenied
            case .some(let error):
                throw GitHubOAuthClientError.oauthFailure(response.errorDescription ?? error)
            case .none:
                throw GitHubOAuthClientError.invalidResponse
            }
        }
    }

    func fetchPullRequests(
        owner: String,
        repo: String,
        accessToken: String,
        state: String = "open"
    ) async throws -> [GitHubPullRequest] {
        var components = URLComponents(
            string: "https://api.github.com/repos/\(owner)/\(repo)/pulls"
        )!
        components.queryItems = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "per_page", value: "30"),
        ]

        guard let url = components.url else {
            throw GitHubOAuthClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitOrigin", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthClientError.httpFailure(http.statusCode, message)
        }

        let decoded = try JSONDecoder().decode([PullRequestResponse].self, from: data)
        return decoded.compactMap { item in
            guard let htmlURL = URL(string: item.htmlURL) else { return nil }
            return GitHubPullRequest(
                number: item.number,
                title: item.title,
                htmlURL: htmlURL,
                headBranch: item.head.ref,
                baseBranch: item.base.ref,
                state: item.state
            )
        }
    }

    func fetchRepositoryMetadata(
        owner: String,
        repo: String,
        accessToken: String
    ) async throws -> GitHubRepository {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitOrigin", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthClientError.httpFailure(http.statusCode, message)
        }

        let decoded = try JSONDecoder().decode(RepositoryResponse.self, from: data)
        return GitHubRepository(owner: owner, name: repo, defaultBranch: decoded.defaultBranch)
    }

    func fetchUserRepositories(accessToken: String) async throws -> [GitHubRemoteRepository] {
        var components = URLComponents(string: "https://api.github.com/user/repos")!
        components.queryItems = [
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
        ]

        guard let url = components.url else {
            throw GitHubOAuthClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitOrigin", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthClientError.httpFailure(http.statusCode, message)
        }

        let decoded = try JSONDecoder().decode([RemoteRepositoryResponse].self, from: data)
        return decoded.compactMap { item in
            guard let htmlURL = URL(string: item.htmlURL),
                  let cloneURL = URL(string: item.cloneURL) else {
                return nil
            }
            let parts = item.fullName.split(separator: "/").map(String.init)
            guard parts.count == 2 else { return nil }
            return GitHubRemoteRepository(
                owner: parts[0],
                fullName: item.fullName,
                name: item.name,
                htmlURL: htmlURL,
                cloneURL: cloneURL,
                defaultBranch: item.defaultBranch
            )
        }
    }

    func createRepository(
        name: String,
        description: String,
        isPrivate: Bool,
        accessToken: String
    ) async throws -> GitHubRemoteRepository {
        let url = URL(string: "https://api.github.com/user/repos")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitOrigin", forHTTPHeaderField: "User-Agent")

        let payload: [String: Any] = [
            "name": name,
            "description": description,
            "private": isPrivate,
            "auto_init": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthClientError.httpFailure(http.statusCode, message)
        }

        let item = try JSONDecoder().decode(RemoteRepositoryResponse.self, from: data)
        guard let htmlURL = URL(string: item.htmlURL),
              let cloneURL = URL(string: item.cloneURL) else {
            throw GitHubOAuthClientError.invalidResponse
        }
        let parts = item.fullName.split(separator: "/").map(String.init)
        guard parts.count == 2 else { throw GitHubOAuthClientError.invalidResponse }
        return GitHubRemoteRepository(
            owner: parts[0],
            fullName: item.fullName,
            name: item.name,
            htmlURL: htmlURL,
            cloneURL: cloneURL,
            defaultBranch: item.defaultBranch
        )
    }

    func fetchRepository(
        owner: String,
        repo: String,
        accessToken: String?
    ) async throws -> GitHubRemoteRepository {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitOrigin", forHTTPHeaderField: "User-Agent")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthClientError.httpFailure(http.statusCode, message)
        }

        let item = try JSONDecoder().decode(RemoteRepositoryResponse.self, from: data)
        guard let htmlURL = URL(string: item.htmlURL),
              let cloneURL = URL(string: item.cloneURL) else {
            throw GitHubOAuthClientError.invalidResponse
        }
        return GitHubRemoteRepository(
            owner: owner,
            fullName: item.fullName,
            name: item.name,
            htmlURL: htmlURL,
            cloneURL: cloneURL,
            defaultBranch: item.defaultBranch
        )
    }

    func fetchCurrentUser(accessToken: String) async throws -> GitHubAuthenticatedUser {
        var request = URLRequest(url: GitHubAuthConfiguration.userAPIURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitOrigin", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthClientError.httpFailure(http.statusCode, message)
        }

        let user = try JSONDecoder().decode(GitHubUserResponse.self, from: data)
        return GitHubAuthenticatedUser(
            login: user.login,
            avatarURL: user.avatarURL.flatMap(URL.init(string:))
        )
    }

    private func post(to url: URL, body: String, acceptJSON: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if acceptJSON {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        request.setValue("GitOrigin", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthClientError.httpFailure(http.statusCode, message)
        }
        return data
    }

    private func formBody(_ values: [String: String]) -> String {
        values
            .map { key, value in
                "\(formEncode(key))=\(formEncode(value))"
            }
            .joined(separator: "&")
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct AccessTokenResponse: Decodable {
    let accessToken: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
        case errorDescription = "error_description"
    }
}

private struct GitHubUserResponse: Decodable {
    let login: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}

private struct PullRequestResponse: Decodable {
    let number: Int
    let title: String
    let htmlURL: String
    let state: String
    let head: PullRequestBranch
    let base: PullRequestBranch

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case htmlURL = "html_url"
        case state
        case head
        case base
    }
}

private struct PullRequestBranch: Decodable {
    let ref: String
}

private struct RepositoryResponse: Decodable {
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
    }
}

private struct RemoteRepositoryResponse: Decodable {
    let fullName: String
    let name: String
    let htmlURL: String
    let cloneURL: String
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case defaultBranch = "default_branch"
    }
}
