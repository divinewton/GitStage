//
//  GitLocator.swift
//  GitOrigin
//
//  Finds a real Git binary on the machine (CLT, Xcode, or Homebrew).
//

import Foundation

enum GitLocator {
    /// Resolves a real Git binary. Never uses `/usr/bin/git` (xcrun shim) or `xcrun`.
    static func locateGitExecutable() -> URL? {
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static var candidatePaths: [String] {
        var paths: [String] = []

        if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            paths.append("\(developerDir)/usr/bin/git")
        }

        paths.append(contentsOf: [
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
        ])

        return paths
    }
}
