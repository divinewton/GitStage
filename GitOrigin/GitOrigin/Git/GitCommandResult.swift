//
//  GitCommandResult.swift
//  GitOrigin
//

import Foundation

struct GitCommandResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}
