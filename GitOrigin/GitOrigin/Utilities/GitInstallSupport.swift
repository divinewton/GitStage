//
//  GitInstallSupport.swift
//  GitOrigin
//
//  Detects a usable Git binary and helps the user install one when missing.
//

import AppKit
import Foundation

enum GitInstallSupport {
    static var isGitAvailable: Bool {
        GitLocator.locateGitExecutable() != nil
    }

    static func installCommandLineTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        try? process.run()
    }

    static func openGitDownloadPage() {
        guard let url = URL(string: "https://git-scm.com/download/mac") else { return }
        NSWorkspace.shared.open(url)
    }
}
