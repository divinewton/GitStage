//
//  GitBranchParserTests.swift
//  GitOriginTests
//
//  Unit tests for GitBranchParser branch listing output.
//

import XCTest
@testable import GitOrigin

final class GitBranchParserTests: XCTestCase {
    func testParsesBranches() {
        let output = """
        main|*|[ahead 2]
        feature/login| |

        """
        let branches = GitBranchParser.parse(output)
        XCTAssertEqual(branches.count, 2)
        XCTAssertEqual(branches[0].name, "main")
        XCTAssertTrue(branches[0].isCurrent)
        XCTAssertEqual(branches[0].trackingNote, "[ahead 2]")
        XCTAssertEqual(branches[1].name, "feature/login")
        XCTAssertFalse(branches[1].isCurrent)
    }

    func testSortsCurrentBranchFirst() {
        let output = """
        feature| |
        main|*|

        """
        let branches = GitBranchParser.parse(output)
        XCTAssertEqual(branches.first?.name, "main")
    }

    func testRemoteOnlyBranchesHideTrackedLocals() {
        let branches = [
            GitBranch(name: "main", isCurrent: true, trackingNote: nil, isRemote: false),
            GitBranch(name: "origin/main", isCurrent: false, trackingNote: nil, isRemote: true),
            GitBranch(name: "origin", isCurrent: false, trackingNote: nil, isRemote: true),
            GitBranch(name: "origin/feature", isCurrent: false, trackingNote: nil, isRemote: true),
        ]

        let remoteOnly = branches.remoteOnlyBranches()
        XCTAssertEqual(remoteOnly.map(\.name), ["origin/feature"])
        XCTAssertEqual(remoteOnly.first?.checkoutDisplayName, "feature")
    }
}
