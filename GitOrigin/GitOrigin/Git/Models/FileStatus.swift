//
//  FileStatus.swift
//  GitOrigin
//

import Foundation

enum FileStatus: String, Hashable, Sendable {
    case modified
    case added
    case deleted
    case untracked
    case renamed
}
