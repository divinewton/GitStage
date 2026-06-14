//
//  GitExecutor.swift
//  GitOrigin
//

import Foundation

actor GitExecutor {
    static let shared = GitExecutor()

    private var resolvedGitURL: URL?

    func run(_ arguments: [String], in directory: URL) async throws -> GitCommandResult {
        try Task.checkCancellation()

        let gitURL = try resolveGitURL()
        let environment = ProcessInfo.processInfo.environment
        let gitArguments = ["-C", directory.path] + arguments
        let workingDirectory = FileManager.default.homeDirectoryForCurrentUser

        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = gitURL
            process.arguments = gitArguments
            process.currentDirectoryURL = workingDirectory
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

            return GitCommandResult(
                stdout: stdout,
                stderr: stderr,
                exitCode: process.terminationStatus
            )
        }.value
    }

    func isInsideWorkTree(in directory: URL) async throws -> Bool {
        let result = try await run(["rev-parse", "--is-inside-work-tree"], in: directory)
        if result.exitCode == 0 {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        }

        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if stderr.localizedCaseInsensitiveContains("not a git repository") {
            return false
        }

        try throwIfFailed(result, arguments: ["rev-parse", "--is-inside-work-tree"])
        return false
    }

    func currentBranch(in directory: URL) async throws -> String {
        let result = try await run(["branch", "--show-current"], in: directory)
        try throwIfFailed(result, arguments: ["branch", "--show-current"])

        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitError.commandFailed(message: "Detached HEAD — no current branch name.")
        }
        return branch
    }

    func status(in directory: URL) async throws -> [ChangedFile] {
        let result = try await run(["status", "--porcelain"], in: directory)
        try throwIfFailed(result, arguments: ["status", "--porcelain"])
        return GitStatusParser.parse(result.stdout)
    }

    private func resolveGitURL() throws -> URL {
        if let resolvedGitURL {
            return resolvedGitURL
        }

        guard let gitURL = GitLocator.locateGitExecutable() else {
            throw GitError.gitNotFound
        }

        resolvedGitURL = gitURL
        return gitURL
    }

    private func throwIfFailed(_ result: GitCommandResult, arguments: [String]) throws {
        guard result.exitCode != 0 else { return }

        let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = (["git"] + arguments).joined(separator: " ")

        if message.localizedCaseInsensitiveContains("cannot be used within an app sandbox")
            || message.localizedCaseInsensitiveContains("xcrun: error") {
            throw GitError.gitNotFound
        }

        if message.localizedCaseInsensitiveContains("not a git repository") {
            throw GitError.notARepository
        }
        if message.localizedCaseInsensitiveContains("merge conflict")
            || message.localizedCaseInsensitiveContains("unmerged") {
            throw GitError.mergeConflict
        }
        if message.localizedCaseInsensitiveContains("authentication failed")
            || message.localizedCaseInsensitiveContains("could not read username")
            || message.localizedCaseInsensitiveContains("permission denied (publickey)") {
            throw GitError.authenticationFailed
        }

        if message.isEmpty {
            throw GitError.commandFailed(message: "\(command) failed with exit code \(result.exitCode).")
        }
        throw GitError.commandFailed(message: message)
    }
}
