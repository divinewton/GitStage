//
//  WorkspaceMode.swift
//  GitOrigin
//
//  Pages shown in the middle workspace column (Changes file list vs commit history).
//

import Foundation

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case history = "History"

    var id: String { rawValue }
}
