//
//  GitStatusParser.swift
//  GitOrigin
//
//  Parses `git status --porcelain` output into ChangedFile models.
//

import Foundation

enum GitStatusParser {
    static func parse(_ output: String) -> [ChangedFile] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0)) }
            .sorted { $0.filepath.localizedStandardCompare($1.filepath) == .orderedAscending }
    }

    private static func parseLine(_ line: String) -> ChangedFile? {
        guard !line.isEmpty else { return nil }

        if line.hasPrefix("??") {
            let path = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return nil }
            return ChangedFile(
                filepath: String(path),
                status: .untracked,
                stagingState: .unstaged
            )
        }

        guard line.count >= 3 else { return nil }

        let indexStatus = line[line.startIndex]
        let workTreeStatus = line[line.index(after: line.startIndex)]
        let pathPart = String(line.dropFirst(3))

        let stagingState = stagingState(index: indexStatus, workTree: workTreeStatus)
        let status = fileStatus(index: indexStatus, workTree: workTreeStatus)

        if indexStatus == "R" || workTreeStatus == "R" {
            guard let filepath = renamedTargetPath(from: pathPart) else { return nil }
            return ChangedFile(filepath: filepath, status: .renamed, stagingState: stagingState)
        }

        let filepath = unquote(pathPart.trimmingCharacters(in: .whitespaces))
        guard !filepath.isEmpty else { return nil }

        return ChangedFile(filepath: filepath, status: status, stagingState: stagingState)
    }

    private static func stagingState(index: Character, workTree: Character) -> StagingState {
        if workTree == "?" {
            return .unstaged
        }

        let indexChanged = index != " " && index != "?"
        let workTreeChanged = workTree != " " && workTree != "?"

        switch (indexChanged, workTreeChanged) {
        case (true, true):
            return .partiallyStaged
        case (true, false):
            return .staged
        case (false, true):
            return .unstaged
        case (false, false):
            return .unstaged
        }
    }

    private static func fileStatus(index: Character, workTree: Character) -> FileStatus {
        if workTree == "?" || index == "?" {
            return .untracked
        }
        if index == "R" || workTree == "R" {
            return .renamed
        }
        if index == "D" || workTree == "D" {
            return .deleted
        }
        if index == "A" || workTree == "A" {
            return .added
        }
        if index == "M" || workTree == "M" {
            return .modified
        }
        return .modified
    }

    private static func renamedTargetPath(from pathPart: String) -> String? {
        let trimmed = pathPart.trimmingCharacters(in: .whitespaces)
        guard let arrowRange = trimmed.range(of: " -> ") else {
            return unquote(trimmed)
        }
        let target = trimmed[arrowRange.upperBound...]
        return unquote(String(target))
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
