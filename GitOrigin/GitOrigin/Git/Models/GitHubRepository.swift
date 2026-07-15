//
//  GitHubRepository.swift
//  GitOrigin
//
//  GitHub metadata for the open repo (owner, name, default branch).
//

import Foundation

struct GitHubRepository: Equatable, Sendable {
    let owner: String
    let name: String
    var defaultBranch: String

    var fullName: String { "\(owner)/\(name)" }
}
