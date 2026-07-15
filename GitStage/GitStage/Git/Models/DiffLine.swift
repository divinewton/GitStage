//
//  DiffLine.swift
//  GitStage
//
//  Parsed diff hunks and line models for DiffView.
//

import Foundation

enum LineType: Hashable, Sendable {
    case addition
    case deletion
    case context
}

struct DiffLine: Identifiable, Hashable, Sendable {
    let id: Int
    let text: String
    let type: LineType
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let noNewlineAtEnd: Bool
}

struct DiffHunk: Identifiable, Hashable, Sendable {
    let id: Int
    let header: String
    let lines: [DiffLine]
}
