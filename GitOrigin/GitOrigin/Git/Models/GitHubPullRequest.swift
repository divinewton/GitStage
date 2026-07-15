//
//  GitHubPullRequest.swift
//  GitOrigin
//
//  Open pull request summary fetched from the GitHub API.
//

import Foundation

struct GitHubPullRequest: Identifiable, Hashable, Sendable {
    let number: Int
    let title: String
    let htmlURL: URL
    let headBranch: String
    let baseBranch: String
    let state: String

    var id: Int { number }
}
