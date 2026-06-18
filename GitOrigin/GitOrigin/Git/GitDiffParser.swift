//
//  GitDiffParser.swift
//  GitOrigin
//
//  Parses unified diff text into hunks with line numbers for DiffView.
//

import Foundation

enum GitDiffParser {
    static func parse(_ output: String) -> [DiffHunk] {
        guard !output.isEmpty else { return [] }

        var hunks: [DiffHunk] = []
        var currentHeader: String?
        var currentLines: [DiffLine] = []
        var lineID = 0
        var hunkID = 0
        var oldLine = 0
        var newLine = 0

        func finishCurrentHunk() {
            guard let header = currentHeader, !currentLines.isEmpty else {
                currentHeader = nil
                currentLines = []
                return
            }

            hunks.append(DiffHunk(id: hunkID, header: header, lines: currentLines))
            hunkID += 1
            currentHeader = nil
            currentLines = []
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("@@") {
                finishCurrentHunk()
                currentHeader = line
                if let range = parseHunkHeader(line) {
                    oldLine = range.oldStart
                    newLine = range.newStart
                }
                continue
            }

            guard currentHeader != nil else { continue }

            if line.hasPrefix("\\") {
                guard var last = currentLines.popLast() else { continue }
                last = DiffLine(
                    id: last.id,
                    text: last.text,
                    type: last.type,
                    oldLineNumber: last.oldLineNumber,
                    newLineNumber: last.newLineNumber,
                    noNewlineAtEnd: true
                )
                currentLines.append(last)
                continue
            }

            let content = line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ")
                ? String(line.dropFirst())
                : line

            if line.hasPrefix("+") {
                currentLines.append(
                    DiffLine(
                        id: lineID,
                        text: content,
                        type: .addition,
                        oldLineNumber: nil,
                        newLineNumber: newLine,
                        noNewlineAtEnd: false
                    )
                )
                newLine += 1
                lineID += 1
            } else if line.hasPrefix("-") {
                currentLines.append(
                    DiffLine(
                        id: lineID,
                        text: content,
                        type: .deletion,
                        oldLineNumber: oldLine,
                        newLineNumber: nil,
                        noNewlineAtEnd: false
                    )
                )
                oldLine += 1
                lineID += 1
            } else {
                currentLines.append(
                    DiffLine(
                        id: lineID,
                        text: content,
                        type: .context,
                        oldLineNumber: oldLine,
                        newLineNumber: newLine,
                        noNewlineAtEnd: false
                    )
                )
                oldLine += 1
                newLine += 1
                lineID += 1
            }
        }

        finishCurrentHunk()
        return hunks
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, newStart: Int)? {
        let pattern = #"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line),
              let oldStart = Int(line[oldRange]),
              let newStart = Int(line[newRange]) else {
            return nil
        }
        return (oldStart, newStart)
    }
}
