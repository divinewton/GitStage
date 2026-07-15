//
//  GitCommandResult.swift
//  GitOrigin
//
//  stdout, stderr, and exit code tuple returned by GitExecutor.run.
//

import Foundation

struct GitCommandResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}
