//
//  GitDiffParserTests.swift
//  GitOriginTests
//
//  Unit tests for GitDiffParser unified diff fixtures.
//

import XCTest
@testable import GitOrigin

final class GitDiffParserTests: XCTestCase {
    private let sampleDiff = """
    diff --git a/Sources/App.swift b/Sources/App.swift
    index 1234567..abcdefg 100644
    --- a/Sources/App.swift
    +++ b/Sources/App.swift
    @@ -1,3 +1,4 @@
     import SwiftUI
    +import Observation

     struct AppView: View {
         var body: some View {
    """

    func testParsesUnifiedDiffFixture() {
        let hunks = GitDiffParser.parse(sampleDiff)

        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].header, "@@ -1,3 +1,4 @@")
        XCTAssertTrue(hunks[0].lines.contains { $0.type == .addition && $0.text == "import Observation" })
        XCTAssertTrue(hunks[0].lines.contains { $0.type == .context && $0.text == "import SwiftUI" })
    }

    func testSkipsFileHeaders() {
        let hunks = GitDiffParser.parse(sampleDiff)
        let renderedText = hunks.flatMap(\.lines).map(\.text).joined(separator: "\n")

        XCTAssertFalse(renderedText.contains("diff --git"))
        XCTAssertFalse(renderedText.contains("index "))
        XCTAssertFalse(renderedText.contains("--- a/"))
        XCTAssertFalse(renderedText.contains("+++ b/"))
    }

    func testAssignsLineNumbers() {
        let output = """
        @@ -1 +1,2 @@
         context
        -removed
        +added
        """

        let hunks = GitDiffParser.parse(output)
        let lines = hunks[0].lines

        XCTAssertEqual(lines[0].oldLineNumber, 1)
        XCTAssertEqual(lines[0].newLineNumber, 1)
        XCTAssertEqual(lines[1].oldLineNumber, 2)
        XCTAssertNil(lines[1].newLineNumber)
        XCTAssertNil(lines[2].oldLineNumber)
        XCTAssertEqual(lines[2].newLineNumber, 2)
    }

    func testNoNewlineMarkerAppliesToPreviousLine() {
        let output = """
        @@ -1,1 +1,1 @@
         hello
        \\ No newline at end of file
        """

        let lines = GitDiffParser.parse(output)[0].lines
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].noNewlineAtEnd)
    }

    func testEmptyOutput() {
        XCTAssertTrue(GitDiffParser.parse("").isEmpty)
    }

    func testLineIDsAreSequential() {
        let hunks = GitDiffParser.parse("""
        @@ -1 +1,2 @@
         one
        +two
        """)
        XCTAssertEqual(hunks[0].lines.map(\.id), [0, 1])
    }
}
