//
//  FileStatus.swift
//  GitOrigin
//
//  Porcelain file change type (modified, added, deleted, etc.).
//

import Foundation

enum FileStatus: String, Hashable, Sendable {
    case modified
    case added
    case deleted
    case untracked
    case renamed
}
