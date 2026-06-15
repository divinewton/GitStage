//
//  RepositoryCatalogItem.swift
//  GitOrigin
//
//  One row in the repository sidebar — a GitHub repo (optionally linked locally) or a local-only folder.
//

import Foundation

struct RepositoryCatalogItem: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// Listed from the GitHub API; may or may not have a linked local folder.
        case github
        /// Cloned locally; points at GitHub but not in the signed-in user's repo list.
        case cloned
        /// No GitHub remote, or not linked to github.com.
        case localOnly
    }

    let id: String
    let title: String
    let subtitle: String?
    let fullName: String?
    let localURL: URL?
    let htmlURL: URL?
    let source: Source

    var isAvailableLocally: Bool { localURL != nil }

    var localPathSubtitle: String? {
        localURL?.deletingLastPathComponent().path
    }
}
