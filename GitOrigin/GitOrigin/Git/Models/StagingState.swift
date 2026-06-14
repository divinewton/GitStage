//
//  StagingState.swift
//  GitOrigin
//

import Foundation

enum StagingState: Hashable, Sendable {
    case unstaged
    case staged
    case partiallyStaged
}
