//
//  GitStatusParserTests.swift
//  GitOriginTests
//

import XCTest
@testable import GitOrigin

final class GitStatusParserTests: XCTestCase {
    func testModifiedUnstaged() {
        let files = GitStatusParser.parse(" M Sources/App.swift\n")
        XCTAssertEqual(files, [
            ChangedFile(filepath: "Sources/App.swift", status: .modified, stagingState: .unstaged),
        ])
    }

    func testModifiedStaged() {
        let files = GitStatusParser.parse("M  README.md\n")
        XCTAssertEqual(files, [
            ChangedFile(filepath: "README.md", status: .modified, stagingState: .staged),
        ])
    }

    func testPartiallyStaged() {
        let files = GitStatusParser.parse("MM lib/util.swift\n")
        XCTAssertEqual(files, [
            ChangedFile(filepath: "lib/util.swift", status: .modified, stagingState: .partiallyStaged),
        ])
    }

    func testUntracked() {
        let files = GitStatusParser.parse("?? notes.txt\n")
        XCTAssertEqual(files, [
            ChangedFile(filepath: "notes.txt", status: .untracked, stagingState: .unstaged),
        ])
    }

    func testDeletedUnstaged() {
        let files = GitStatusParser.parse(" D removed.swift\n")
        XCTAssertEqual(files, [
            ChangedFile(filepath: "removed.swift", status: .deleted, stagingState: .unstaged),
        ])
    }

    func testAddedStaged() {
        let files = GitStatusParser.parse("A  new.swift\n")
        XCTAssertEqual(files, [
            ChangedFile(filepath: "new.swift", status: .added, stagingState: .staged),
        ])
    }

    func testRenamed() {
        let files = GitStatusParser.parse("R  old.swift -> new.swift\n")
        XCTAssertEqual(files, [
            ChangedFile(filepath: "new.swift", status: .renamed, stagingState: .staged),
        ])
    }

    func testQuotedPathWithSpaces() {
        let files = GitStatusParser.parse(" M \"My Project/file.swift\"\n")
        XCTAssertEqual(files, [
            ChangedFile(filepath: "My Project/file.swift", status: .modified, stagingState: .unstaged),
        ])
    }

    func testMultipleFilesSortedAlphabetically() {
        let output = """
         M zeta.swift
         M alpha.swift
        ?? middle.txt

        """
        let files = GitStatusParser.parse(output)
        XCTAssertEqual(files.map(\.filepath), ["alpha.swift", "middle.txt", "zeta.swift"])
    }

    func testEmptyOutput() {
        XCTAssertTrue(GitStatusParser.parse("").isEmpty)
    }
}
