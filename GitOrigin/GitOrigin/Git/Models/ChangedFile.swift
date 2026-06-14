//
//  ChangedFile.swift
//  GitOrigin
//

import Foundation

struct ChangedFile: Identifiable, Hashable, Sendable {
    var id: String { filepath }
    let filepath: String
    let status: FileStatus
    let stagingState: StagingState
}
