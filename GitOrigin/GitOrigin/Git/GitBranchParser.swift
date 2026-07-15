//
//  GitBranchParser.swift
//  GitOrigin
//
//  Parses `git branch` formatted output into GitBranch models.
//

import Foundation

enum GitBranchParser {
    /// Parses `git branch --format='%(refname:short)|%(HEAD)|%(upstream:track)'`.
    static func parse(_ output: String, isRemote: Bool = false) -> [GitBranch] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let parts = String(line).split(separator: "|", omittingEmptySubsequences: false)
                guard let namePart = parts.first else { return nil }
                let name = String(namePart)
                guard !name.isEmpty else { return nil }
                guard name != "origin/HEAD" else { return nil }

                let headMarker = parts.count > 1 ? String(parts[1]) : ""
                let tracking = parts.count > 2 ? String(parts[2]).trimmingCharacters(in: .whitespaces) : ""
                let isCurrent = !isRemote && headMarker == "*"

                return GitBranch(
                    name: name,
                    isCurrent: isCurrent,
                    trackingNote: tracking.isEmpty ? nil : tracking,
                    isRemote: isRemote
                )
            }
            .sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
