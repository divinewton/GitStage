//
//  GitExecutor.swift
//  GitOrigin
//
//  Runs the system Git CLI via Process and maps stdout/stderr into Swift models.
//  Injects GitHub HTTPS credentials through GIT_CONFIG_* when fetch/pull/push need auth.
//

import Foundation

/// Thread-safe wrapper around a single resolved Git binary path.
actor GitExecutor {
    static let shared = GitExecutor()

    private var resolvedGitURL: URL?
    private var githubAccessToken: String?

    func setGitHubAccessToken(_ token: String?) {
        githubAccessToken = token
    }

    func run(
        _ arguments: [String],
        in directory: URL,
        usesGitHubCredentials: Bool = false,
        extraEnvironment: [String: String] = [:]
    ) async throws -> GitCommandResult {
        try Task.checkCancellation()

        let gitURL = try resolveGitURL()
        var environment = gitEnvironment(usesGitHubCredentials: usesGitHubCredentials)
        for (key, value) in extraEnvironment {
            environment[key] = value
        }

        // Use `git -C` instead of `currentDirectoryURL` — sandboxed apps often cannot
        // set the process working directory to a security-scoped repository path.
        let process = Process()
        process.executableURL = gitURL
        process.arguments = ["-C", directory.path] + arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
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

    func diff(for file: ChangedFile, in directory: URL) async throws -> String {
        let arguments = diffArguments(for: file)
        let result = try await run(arguments, in: directory)

        if result.exitCode == 0 || result.exitCode == 1 {
            return result.stdout
        }

        try throwIfFailed(result, arguments: arguments)
        return result.stdout
    }

    func stage(path: String, in directory: URL) async throws {
        let result = try await run(["add", "--", path], in: directory)
        try throwIfFailed(result, arguments: ["add", "--", path])
    }

    func unstage(path: String, in directory: URL) async throws {
        let result = try await run(["restore", "--staged", "--", path], in: directory)
        try throwIfFailed(result, arguments: ["restore", "--staged", "--", path])
    }

    func stageAll(in directory: URL) async throws {
        let result = try await run(["add", "--all"], in: directory)
        try throwIfFailed(result, arguments: ["add", "--all"])
    }

    func unstageAll(in directory: URL) async throws {
        let result = try await run(["restore", "--staged", "--", "."], in: directory)
        try throwIfFailed(result, arguments: ["restore", "--staged", "--", "."])
    }

    func hasStagedChanges(in directory: URL) async throws -> Bool {
        let result = try await run(["diff", "--cached", "--quiet"], in: directory)
        return result.exitCode == 1
    }

    func commit(
        summary: String,
        body: String?,
        author: (name: String, email: String)?,
        in directory: URL
    ) async throws {
        var arguments = ["commit", "-m", summary]
        if let body, !body.isEmpty {
            arguments.append(contentsOf: ["-m", body])
        }

        var extraEnvironment: [String: String] = [:]
        if let author {
            extraEnvironment["GIT_AUTHOR_NAME"] = author.name
            extraEnvironment["GIT_AUTHOR_EMAIL"] = author.email
            extraEnvironment["GIT_COMMITTER_NAME"] = author.name
            extraEnvironment["GIT_COMMITTER_EMAIL"] = author.email
        }

        let result = try await run(arguments, in: directory, extraEnvironment: extraEnvironment)
        try throwIfFailed(result, arguments: ["commit"])
    }

    func log(branch: String? = nil, limit: Int = 50, in directory: URL) async throws -> [GitCommitEntry] {
        var arguments = ["log", "--oneline", "-n", "\(limit)"]
        if let branch, !branch.isEmpty {
            arguments.append(branch)
        }
        let result = try await run(arguments, in: directory)
        try throwIfFailed(result, arguments: arguments)
        return GitLogParser.parse(result.stdout)
    }

    func branches(in directory: URL) async throws -> [GitBranch] {
        async let local = localBranches(in: directory)
        async let remote = remoteBranches(in: directory)
        let merged = try await local + remote
        return merged.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            if lhs.isRemote != rhs.isRemote { return !lhs.isRemote }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func localBranches(in directory: URL) async throws -> [GitBranch] {
        let result = try await run(
            ["branch", "--format", "%(refname:short)|%(HEAD)|%(upstream:track)"],
            in: directory
        )
        try throwIfFailed(result, arguments: ["branch"])
        return GitBranchParser.parse(result.stdout, isRemote: false)
    }

    func remoteBranches(in directory: URL) async throws -> [GitBranch] {
        let result = try await run(
            ["branch", "-r", "--format", "%(refname:short)|%(HEAD)|%(upstream:track)"],
            in: directory
        )
        guard result.exitCode == 0 else { return [] }
        return GitBranchParser.parse(result.stdout, isRemote: true)
    }

    func createBranch(named name: String, from startPoint: String?, in directory: URL) async throws {
        var arguments = ["checkout", "-b", name]
        if let startPoint, !startPoint.isEmpty {
            arguments.append(startPoint)
        }
        let result = try await run(arguments, in: directory)
        try throwIfFailed(result, arguments: arguments)
    }

    func checkout(branch: GitBranch, in directory: URL) async throws {
        let arguments: [String]
        if branch.isRemote {
            guard let localName = branch.localCheckoutName else {
                throw GitError.commandFailed(message: "Could not derive a local branch name from “\(branch.name)”.")
            }
            arguments = ["checkout", "--track", "-B", localName, branch.name]
        } else {
            arguments = ["checkout", branch.name]
        }

        let result = try await run(arguments, in: directory)
        try throwIfFailed(result, arguments: arguments)
    }

    func checkout(branchName: String, in directory: URL) async throws {
        let result = try await run(["checkout", branchName], in: directory)
        try throwIfFailed(result, arguments: ["checkout", branchName])
    }

    func originURL(in directory: URL) async throws -> String? {
        let result = try await run(["config", "--get", "remote.origin.url"], in: directory)
        guard result.exitCode == 0 else { return nil }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    func defaultBranch(in directory: URL, remote: String = "origin") async throws -> String? {
        let result = try await run(["symbolic-ref", "refs/remotes/\(remote)/HEAD"], in: directory)
        if result.exitCode == 0 {
            let ref = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return ref.split(separator: "/").last.map(String.init)
        }
        return try? await currentBranch(in: directory)
    }

    func upstreamStatus(in directory: URL) async throws -> UpstreamStatus {
        let upstreamResult = try await run(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            in: directory
        )
        guard upstreamResult.exitCode == 0 else {
            return .none
        }

        let upstreamName = upstreamResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let countResult = try await run(
            ["rev-list", "--left-right", "--count", "@{u}...HEAD"],
            in: directory
        )
        try throwIfFailed(countResult, arguments: ["rev-list"])

        let parts = countResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t")
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            return UpstreamStatus(upstreamName: upstreamName, ahead: 0, behind: 0)
        }

        return UpstreamStatus(upstreamName: upstreamName, ahead: ahead, behind: behind)
    }

    func fetch(in directory: URL) async throws {
        let result = try await run(["fetch"], in: directory, usesGitHubCredentials: true)
        try throwIfFailed(result, arguments: ["fetch"])
    }

    func pull(in directory: URL) async throws {
        let result = try await run(["pull"], in: directory, usesGitHubCredentials: true)
        try throwIfFailed(result, arguments: ["pull"])
    }

    func push(in directory: URL) async throws {
        let result = try await run(["push"], in: directory, usesGitHubCredentials: true)
        try throwIfFailed(result, arguments: ["push"])
    }

    func push(setUpstream branch: String, remote: String = "origin", in directory: URL) async throws {
        let result = try await run(["push", "-u", remote, branch], in: directory, usesGitHubCredentials: true)
        try throwIfFailed(result, arguments: ["push", "-u", remote, branch])
    }

    private func diffArguments(for file: ChangedFile) -> [String] {
        switch file.stagingState {
        case .staged:
            ["diff", "--cached", "--no-color", "--", file.filepath]
        case .unstaged, .partiallyStaged:
            if file.status == .untracked {
                ["diff", "--no-color", "--no-index", "--", "/dev/null", file.filepath]
            } else {
                ["diff", "--no-color", "--", file.filepath]
            }
        }
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

    private func gitEnvironment(usesGitHubCredentials: Bool) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"

        guard usesGitHubCredentials,
              let token = githubAccessToken,
              !token.isEmpty else {
            return environment
        }

        let credentials = "x-access-token:\(token)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        environment["GIT_CONFIG_KEY_0"] = "http.https://github.com/.extraHeader"
        environment["GIT_CONFIG_VALUE_0"] = "Authorization: Basic \(encoded)"
        environment["GIT_CONFIG_COUNT"] = "1"
        return environment
    }

    private func throwIfFailed(_ result: GitCommandResult, arguments: [String]) throws {
        guard result.exitCode != 0 else { return }

        let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = (["git"] + arguments).joined(separator: " ")

        if message.localizedCaseInsensitiveContains("operation not permitted") {
            throw GitError.commandFailed(message: message)
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

        let combinedOutput = [result.stderr, result.stdout]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if arguments.first == "commit" {
            if combinedOutput.localizedCaseInsensitiveContains("nothing to commit")
                || combinedOutput.localizedCaseInsensitiveContains("no changes added to commit") {
                throw GitError.nothingToCommit
            }
            if combinedOutput.localizedCaseInsensitiveContains("author identity unknown")
                || combinedOutput.localizedCaseInsensitiveContains("please tell me who you are")
                || combinedOutput.localizedCaseInsensitiveContains("unable to auto-detect email") {
                throw GitError.missingGitIdentity
            }
        }

        if message.isEmpty {
            if !combinedOutput.isEmpty {
                throw GitError.commandFailed(message: combinedOutput)
            }
            throw GitError.commandFailed(message: "\(command) failed with exit code \(result.exitCode).")
        }
        throw GitError.commandFailed(message: message)
    }
}
