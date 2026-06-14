//
//  GitLocatorTests.swift
//  GitOriginTests
//

import XCTest
@testable import GitOrigin

final class GitLocatorTests: XCTestCase {
    func testLocateGitExecutableFindsKnownPath() throws {
        guard let url = GitLocator.locateGitExecutable() else {
            throw XCTSkip("No git binary found on this machine.")
        }

        XCTAssertTrue(url.path.hasSuffix("/git"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
        XCTAssertFalse(url.path == "/usr/bin/git", "Should prefer real git over the /usr/bin shim.")
    }
}
