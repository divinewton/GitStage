//
//  GitError.swift
//  GitOrigin
//

import Foundation

enum GitError: Error, Equatable, LocalizedError {
    case gitNotFound
    case notARepository
    case mergeConflict
    case authenticationFailed
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
            "Authentication failed. Check your credentials or SSH keys."
        case .commandFailed(let message):
            message
        case .accessDenied:
            "GitOrigin does not have permission to access this folder."
        }
    }
}
