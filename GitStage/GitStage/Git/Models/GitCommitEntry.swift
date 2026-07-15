//
//  GitCommitEntry.swift
//  GitStage
//
//  Short hash and subject from git log.
//

import Foundation

struct GitCommitEntry: Identifiable, Hashable, Sendable {
    var id: String { hash }
    let hash: String
    let subject: String
}
