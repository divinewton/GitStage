//
//  ChangedFile.swift
//  GitOrigin
//
//  One changed path in the working tree with status and staging state.
//

import Foundation

struct ChangedFile: Identifiable, Hashable, Sendable {
    var id: String { filepath }
    let filepath: String
    let status: FileStatus
    let stagingState: StagingState
}
