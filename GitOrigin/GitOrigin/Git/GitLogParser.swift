//
//  GitLogParser.swift
//  GitOrigin
//
//  Parses `git log --oneline` output into GitCommitEntry models.
//

import Foundation

enum GitLogParser {
    static func parse(_ output: String) -> [GitCommitEntry] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let text = String(line)
                guard let space = text.firstIndex(of: " ") else { return nil }
                let hash = String(text[..<space])
                let subject = String(text[text.index(after: space)...])
                guard !hash.isEmpty else { return nil }
                return GitCommitEntry(hash: hash, subject: subject)
            }
    }
}
