//
//  ChangedFileBadge.swift
//  GitOrigin
//
//  Compact status letter for a changed file row.
//

import SwiftUI

struct ChangedFileBadge: View {
    let file: ChangedFile

    var body: some View {
        Text(statusLetter)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(statusColor, in: Circle())
            .accessibilityLabel(accessibilityLabel)
    }

    private var statusLetter: String {
        switch file.status {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .untracked: "?"
        case .renamed: "R"
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .modified: .orange
        case .added: .green
        case .deleted: .red
        case .untracked: .blue
        case .renamed: .purple
        }
    }

    private var accessibilityLabel: String {
        let staging: String = switch file.stagingState {
        case .staged: "staged"
        case .unstaged: "unstaged"
        case .partiallyStaged: "partially staged"
        }
        return "\(file.filepath), \(file.status), \(staging)"
    }
}
