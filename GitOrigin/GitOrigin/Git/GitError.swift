//
//  GitError.swift
//  GitOrigin
//
//  Typed errors surfaced from GitExecutor; user-facing strings come from errorDescription.
//

import Foundation

enum GitError: Error, Equatable, LocalizedError {
    case gitNotFound
    case notARepository
    case mergeConflict
    case authenticationFailed
    case nothingToCommit
    case missingGitIdentity
    case commandFailed(message: String)
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            "Git was not found. Install Xcode Command Line Tools or Homebrew Git."
        case .notARepository:
            "The selected folder is not a Git repository."
        case .mergeConflict:
            "The repository has unresolved merge conflicts."
        case .authenticationFailed:
            "Authentication failed. Sign in with GitHub or check your remote credentials."
        case .nothingToCommit:
            "Nothing is staged to commit. Stage your changes first, then try again."
        case .missingGitIdentity:
            "Git does not have a commit identity configured for this repository."
        case .commandFailed(let message):
            message
        case .accessDenied:
            "GitOrigin does not have write permission for this repository."
        }
    }
}
