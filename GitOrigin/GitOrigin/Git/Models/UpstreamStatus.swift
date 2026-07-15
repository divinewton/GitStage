//
//  UpstreamStatus.swift
//  GitOrigin
//
//  Ahead/behind counts relative to the tracking branch.
//

import Foundation

struct UpstreamStatus: Equatable, Sendable {
    let upstreamName: String?
    let ahead: Int
    let behind: Int

    static let none = UpstreamStatus(upstreamName: nil, ahead: 0, behind: 0)

    var summary: String? {
        guard upstreamName != nil else { return nil }
        if ahead == 0 && behind == 0 { return "Up to date" }
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.joined(separator: " ")
    }
}
