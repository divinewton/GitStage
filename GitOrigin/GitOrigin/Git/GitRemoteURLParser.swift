//
//  GitRemoteURLParser.swift
//  GitOrigin
//
//  Extracts GitHub owner/name from remote URLs and builds PR links.
//

import Foundation

enum GitRemoteURLParser {
    static func parseGitHubRepository(from remoteURL: String) -> (owner: String, name: String)? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("git@github.com:") {
            return parseSSHPath(String(trimmed.dropFirst("git@github.com:".count)))
        }

        guard let components = URLComponents(string: trimmed),
              components.host?.lowercased() == "github.com" else {
            return nil
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return (owner: parts[0], name: stripGitSuffix(parts[1]))
    }

    static func createPullRequestURL(
        repository: GitHubRepository,
        headBranch: String,
        baseBranch: String? = nil
    ) -> URL {
        let base = baseBranch ?? repository.defaultBranch
        let urlString = "https://github.com/\(repository.fullName)/compare/\(base)...\(headBranch)?expand=1"
        return URL(string: urlString)!
    }

    /// Parses `https://github.com/owner/repo` or `owner/repo` input.
    static func parseGitHubReference(from input: String) -> (owner: String, name: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("github.com") {
            return parseGitHubRepository(from: trimmed)
        }

        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        return (owner: parts[0], name: stripGitSuffix(parts[1]))
    }

    static func httpsCloneURL(owner: String, name: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(name).git")!
    }

    private static func parseSSHPath(_ path: String) -> (owner: String, name: String)? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return (owner: parts[0], name: stripGitSuffix(parts[1]))
    }

    private static func stripGitSuffix(_ name: String) -> String {
        name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }
}
