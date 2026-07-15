//
//  RepositoryCatalogItem.swift
//  GitOrigin
//
//  One repository the user added to GitOrigin (local folder + optional GitHub metadata).
//

import Foundation

struct RepositoryCatalogItem: Identifiable, Equatable, Sendable {
    let id: String
    let owner: String
    let name: String
    let fullName: String?
    let localURL: URL
    let htmlURL: URL?

    var title: String { name }

    var isAvailableLocally: Bool { true }
}
