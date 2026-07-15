//
//  StagingState.swift
//  GitOrigin
//
//  Whether a changed file is staged, unstaged, or partially staged.
//

import Foundation

enum StagingState: Hashable, Sendable {
    case unstaged
    case staged
    case partiallyStaged
}
