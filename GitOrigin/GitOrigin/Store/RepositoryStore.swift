//
//  RepositoryStore.swift
//  GitOrigin
//
//  Central app state: open repository, changed files, diffs, branches, sync, and GitHub metadata.
//  UI binds to this type; git/network work is delegated to GitExecutor and GitHubOAuthClient.
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class RepositoryStore {
    // MARK: - Open repository state

    var repoURL: URL?
    var changedFiles: [ChangedFile] = []
    var currentBranch: String?
    var selectedFile: ChangedFile?
    var currentDiff: [DiffLine] = []
    var isLoadingStatus = false
    var isLoadingDiff = false
    var isCommitting = false
    var isSyncing = false
    var isLoadingHistory = false
    var isLoadingBranches = false
    var isLoadingPullRequests = false
    var isLoadingCatalog = false
    var presentedAlert: RepositoryAlert?

    // MARK: - Branches, history, and catalog

    var commits: [GitCommitEntry] = []
    var branches: [GitBranch] = []
    var catalogItems: [RepositoryCatalogItem] = []
    var upstreamStatus = UpstreamStatus.none
    var pendingCheckoutBranch: GitBranch?
    var showDirtyCheckoutConfirmation = false

    var githubRepository: GitHubRepository?
    var pullRequests: [GitHubPullRequest] = []
    var defaultBranchName: String?

    var historyBranchName: String?
    var preferredWorkspaceMode: WorkspaceMode?

    // MARK: - Commit UI

    var showCreateBranchSheet = false
    var newBranchName = ""
    var newBranchBase = ""

    var commitSummary = ""
    var commitDescription = ""
    var isCommitFieldFocused = false

    private let auth: GitHubAuthService
    private let git = GitExecutor.shared
    private let github = GitHubOAuthClient.shared
    private let repoAccess = RepoAccessManager()
    private let repoWatcher = GitRepoWatcher()
    private var diffLoadTask: Task<Void, Never>?
    private var isRefreshingStatus = false
    private var originCache: [String: String] = [:]

    init(auth: GitHubAuthService) {
        self.auth = auth
    }

    var recentRepositories: [URL] {
        repoAccess.recentRepositories()
    }

    var recentRepositoryPathOrder: [String] {
        repoAccess.recentRepositoryPathOrder()
    }

    var localBranches: [GitBranch] {
        branches.filter { !$0.isRemote }
    }

    var remoteBranches: [GitBranch] {
        branches.filter(\.isRemote)
    }

    var historyDisplayBranch: String {
        historyBranchName ?? currentBranch ?? "branch"
    }

    var pullRequestForCurrentBranch: GitHubPullRequest? {
        guard let branch = currentBranch else { return nil }
        return pullRequests.first { $0.headBranch == branch }
    }

    var stagedFileCount: Int {
        changedFiles.filter { $0.stagingState == .staged || $0.stagingState == .partiallyStaged }.count
    }

    func presentError(_ error: GitError) {
        presentedAlert = RepositoryAlert(
            title: "Error",
            message: error.errorDescription ?? "An unknown error occurred."
        )
    }

    /// Shows a generic alert in ContentView via `.alert(item:)`.
    func presentAlert(title: String, message: String) {
        presentedAlert = RepositoryAlert(title: title, message: message)
    }

    func refreshRepositoryCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

        guard let token = try? GitHubKeychain.loadAccessToken() else {
            catalogItems = localOnlyCatalogItems()
            return
        }

        do {
            let remoteRepos = try await github.fetchUserRepositories(accessToken: token)
            var items: [RepositoryCatalogItem] = []

            for repo in remoteRepos {
                let localURL = repoAccess.linkedLocalURL(forGitHubFullName: repo.fullName)
                items.append(
                    RepositoryCatalogItem(
                        id: "github-\(repo.fullName)",
                        title: repo.name,
                        subtitle: repo.fullName,
                        fullName: repo.fullName,
                        localURL: localURL,
                        htmlURL: repo.htmlURL,
                        source: .github
                    )
                )
            }

            let linkedPaths = Set(
                items.compactMap { item in
                    item.localURL.map { RepoAccessManager.normalizedPath($0) }
                }
            )
            let apiFullNames = Set(remoteRepos.map(\.fullName))
            items.append(contentsOf: clonedCatalogItems(apiFullNames: apiFullNames, excludingPaths: linkedPaths))

            let shownPaths = Set(
                items.compactMap { item in
                    item.localURL.map { RepoAccessManager.normalizedPath($0) }
                }
            )
            items.append(contentsOf: localOnlyCatalogItems(excludingPaths: shownPaths))
            catalogItems = sortCatalogByRecency(items)
        } catch {
            catalogItems = localOnlyCatalogItems()
            presentAlert(title: "GitHub Repositories", message: error.localizedDescription)
        }
    }

    func openCatalogItem(_ item: RepositoryCatalogItem) async {
        if let localURL = item.localURL {
            await openRepository(at: localURL)
            return
        }

        if item.source == .github || item.source == .cloned {
            await locateLocalFolder(for: item)
            return
        }

        await openRepositoryViaPanel()
    }

    func locateLocalFolder(for item: RepositoryCatalogItem) async {
        guard let url = repoAccess.promptForRepository() else { return }

        guard let accessed = repoAccess.beginAccess(to: url) else {
            presentError(.accessDenied)
            return
        }

        do {
            guard try await git.isInsideWorkTree(in: accessed) else {
                presentAlert(
                    title: "Not a Git Repository",
                    message: "The selected folder is not a Git repository."
                )
                repoAccess.endAccess()
                return
            }

            if let expectedFullName = item.fullName {
                guard let origin = try await git.originURL(in: accessed),
                      matches(fullName: expectedFullName, originURL: origin) else {
                    presentAlert(
                        title: "Different Repository",
                        message: "This folder’s Git remote does not match “\(expectedFullName)”. Choose the correct folder or clone the repository first."
                    )
                    repoAccess.endAccess()
                    return
                }
                repoAccess.linkGitHubRepository(fullName: expectedFullName, localURL: accessed)
            }

            await openRepository(at: accessed)
        } catch let error as GitError {
            repoAccess.endAccess()
            presentError(error)
        } catch {
            repoAccess.endAccess()
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    func openCatalogItemOnGitHub(_ item: RepositoryCatalogItem) {
        guard let htmlURL = item.htmlURL else { return }
        NSWorkspace.shared.open(htmlURL)
    }

    func revealCatalogItemInFinder(_ item: RepositoryCatalogItem) {
        guard let localURL = item.localURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([localURL])
    }

    func unlinkLocalFolder(for item: RepositoryCatalogItem) async {
        guard let fullName = item.fullName else { return }
        repoAccess.unlinkGitHubRepository(fullName: fullName)
        await refreshRepositoryCatalog()
    }

    func openRepositoryViaPanel() async {
        guard let url = repoAccess.promptForRepository() else { return }
        await openRepository(at: url)
    }

    func openRepository(at url: URL) async {
        presentedAlert = nil
        closeRepository()

        guard let workingURL = repoAccess.beginAccess(to: url) else {
            presentError(.accessDenied)
            return
        }

        do {
            guard try await git.isInsideWorkTree(in: workingURL) else {
                presentAlert(
                    title: "Not a Git Repository",
                    message: "The selected folder is not a Git repository. Choose a folder that contains a `.git` directory."
                )
                repoAccess.endAccess()
                return
            }

            guard repoAccess.canWriteToGitDirectory(at: workingURL) else {
                presentError(.accessDenied)
                repoAccess.endAccess()
                return
            }

            repoURL = workingURL
            repoAccess.addRecentRepository(workingURL)
            if let origin = try await git.originURL(in: workingURL) {
                originCache[workingURL.path] = origin
                if let parsed = GitRemoteURLParser.parseGitHubRepository(from: origin) {
                    let fullName = "\(parsed.owner)/\(parsed.name)"
                    repoAccess.linkGitHubRepository(fullName: fullName, localURL: workingURL)
                }
            }

            historyBranchName = nil
            startWatchingRepository(at: workingURL)
            await refreshStatus(userInitiated: true)
            await refreshBranches()
            await refreshHistory(for: currentBranch)
            await syncWithRemoteAfterOpen()
            await refreshRepositoryMetadata()
            await refreshPullRequests()
            await refreshRepositoryCatalog()
        } catch let error as GitError {
            repoAccess.endAccess()
            presentError(error)
        } catch {
            repoAccess.endAccess()
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    func restoreRecentRepositoryIfAvailable() async {
        guard repoURL == nil else { return }
        guard let url = repoAccess.restoreRecentRepository() else { return }
        await openRepository(at: url)
    }

    func closeRepository() {
        cancelDiffLoad()
        selectedFile = nil
        changedFiles = []
        currentBranch = nil
        currentDiff = []
        commits = []
        branches = []
        upstreamStatus = .none
        pendingCheckoutBranch = nil
        showDirtyCheckoutConfirmation = false
        githubRepository = nil
        pullRequests = []
        defaultBranchName = nil
        historyBranchName = nil
        commitSummary = ""
        commitDescription = ""
        repoURL = nil
        repoWatcher.stop()
        repoAccess.endAccess()
    }

    func refreshStatus(userInitiated: Bool = false) async {
        guard let repoURL else { return }
        guard !isRefreshingStatus else { return }

        isRefreshingStatus = true
        if userInitiated { isLoadingStatus = true }
        repoWatcher.pause()
        defer {
            isRefreshingStatus = false
            if userInitiated { isLoadingStatus = false }
            repoWatcher.resume()
        }

        do {
            async let branch = git.currentBranch(in: repoURL)
            async let files = git.status(in: repoURL)
            async let upstream = git.upstreamStatus(in: repoURL)

            let resolvedBranch = try await branch
            let resolvedFiles = try await files
            let resolvedUpstream = try await upstream

            currentBranch = resolvedBranch
            changedFiles = resolvedFiles
            upstreamStatus = resolvedUpstream

            if historyBranchName == nil || historyBranchName == currentBranch {
                historyBranchName = resolvedBranch
            }

            if let selectedID = selectedFile?.id,
               let file = resolvedFiles.first(where: { $0.id == selectedID }) {
                let shouldReloadDiff = selectedFile?.stagingState != file.stagingState
                    || selectedFile?.status != file.status
                selectedFile = file
                if shouldReloadDiff {
                    loadDiff(for: file)
                }
            } else {
                cancelDiffLoad()
                selectedFile = nil
                currentDiff = []
            }
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    func refreshRepositoryMetadata() async {
        guard let repoURL else { return }

        do {
            defaultBranchName = try await git.defaultBranch(in: repoURL)

            guard let originURL = try await git.originURL(in: repoURL),
                  let parsed = GitRemoteURLParser.parseGitHubRepository(from: originURL) else {
                githubRepository = nil
                return
            }

            originCache[repoURL.path] = originURL

            if let token = try? GitHubKeychain.loadAccessToken() {
                githubRepository = try await github.fetchRepositoryMetadata(
                    owner: parsed.owner,
                    repo: parsed.name,
                    accessToken: token
                )
                defaultBranchName = githubRepository?.defaultBranch ?? defaultBranchName
            } else {
                githubRepository = GitHubRepository(
                    owner: parsed.owner,
                    name: parsed.name,
                    defaultBranch: defaultBranchName ?? "main"
                )
            }
        } catch {
            githubRepository = nil
        }
    }

    func refreshPullRequests() async {
        guard let githubRepository else {
            pullRequests = []
            return
        }
        guard let token = try? GitHubKeychain.loadAccessToken() else {
            pullRequests = []
            return
        }

        isLoadingPullRequests = true
        defer { isLoadingPullRequests = false }

        do {
            pullRequests = try await github.fetchPullRequests(
                owner: githubRepository.owner,
                repo: githubRepository.name,
                accessToken: token
            )
        } catch {
            pullRequests = []
        }
    }

    func refreshHistory(for branchName: String? = nil) async {
        guard let repoURL else { return }

        let branch = branchName ?? historyBranchName ?? currentBranch
        historyBranchName = branch

        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            commits = try await git.log(branch: branch, in: repoURL)
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    func refreshBranches() async {
        guard let repoURL else { return }

        isLoadingBranches = true
        defer { isLoadingBranches = false }

        do {
            branches = try await git.branches(in: repoURL)
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    func viewHistory(for branchName: String) {
        historyBranchName = branchName
        preferredWorkspaceMode = .history
        Task { await refreshHistory(for: branchName) }
    }

    func presentCreateBranchSheet() {
        newBranchName = ""
        newBranchBase = currentBranch ?? defaultBranchName ?? "main"
        showCreateBranchSheet = true
    }

    func createBranch() async {
        guard let repoURL else { return }

        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let base = newBranchBase.trimmingCharacters(in: .whitespacesAndNewlines)
        showCreateBranchSheet = false

        do {
            try await git.createBranch(
                named: name,
                from: base.isEmpty ? nil : base,
                in: repoURL
            )
            historyBranchName = name
            await refreshStatus()
            await refreshBranches()
            await refreshHistory(for: name)
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    func requestCheckout(branch: GitBranch) {
        guard !branch.isCurrent else { return }

        if changedFiles.isEmpty {
            Task { await performCheckout(branch) }
        } else {
            pendingCheckoutBranch = branch
            showDirtyCheckoutConfirmation = true
        }
    }

    func checkoutBranch(named branchName: String) {
        guard let branch = branches.first(where: { $0.name == branchName }) else {
            Task { await checkoutRemoteOrLocalName(branchName) }
            return
        }
        requestCheckout(branch: branch)
    }

    func confirmCheckout() async {
        guard let branch = pendingCheckoutBranch else { return }
        pendingCheckoutBranch = nil
        showDirtyCheckoutConfirmation = false
        await performCheckout(branch)
    }

    func cancelCheckout() {
        pendingCheckoutBranch = nil
        showDirtyCheckoutConfirmation = false
    }

    func openPullRequestInBrowser(_ pullRequest: GitHubPullRequest) {
        NSWorkspace.shared.open(pullRequest.htmlURL)
    }

    func openCreatePullRequestInBrowser(for branchName: String? = nil) {
        guard let githubRepository else { return }
        let head = branchName ?? currentBranch ?? historyBranchName ?? githubRepository.defaultBranch
        let url = GitRemoteURLParser.createPullRequestURL(
            repository: githubRepository,
            headBranch: head
        )
        NSWorkspace.shared.open(url)
    }

    func openCurrentBranchPullRequestInBrowser() {
        if let pullRequest = pullRequestForCurrentBranch {
            openPullRequestInBrowser(pullRequest)
        } else {
            openCreatePullRequestInBrowser()
        }
    }

    func fetch() async { await sync { try await git.fetch(in: $0) } }
    func pull() async { await sync { try await git.pull(in: $0) } }

    func push() async {
        await sync { url in
            if upstreamStatus.upstreamName == nil, let branch = currentBranch {
                try await git.push(setUpstream: branch, in: url)
            } else {
                try await git.push(in: url)
            }
        }
    }

    func selectFile(_ file: ChangedFile?) {
        selectedFile = file
        if let file {
            loadDiff(for: file)
        } else {
            cancelDiffLoad()
            currentDiff = []
        }
    }

    func selectFile(id: String?) {
        guard let id else {
            selectFile(nil)
            return
        }
        selectFile(changedFiles.first { $0.id == id })
    }

    func loadDiff(for file: ChangedFile) {
        guard let repoURL else { return }

        let fileID = file.id
        diffLoadTask?.cancel()
        currentDiff = []
        isLoadingDiff = true

        diffLoadTask = Task {
            do {
                let output = try await git.diff(for: file, in: repoURL)
                guard !Task.isCancelled, selectedFile?.id == fileID else { return }
                currentDiff = GitDiffParser.parse(output)
            } catch let error as GitError {
                guard !Task.isCancelled, selectedFile?.id == fileID else { return }
                presentError(error)
                currentDiff = []
            } catch {
                guard !Task.isCancelled, selectedFile?.id == fileID else { return }
                presentError(.commandFailed(message: error.localizedDescription))
                currentDiff = []
            }

            if !Task.isCancelled, selectedFile?.id == fileID {
                isLoadingDiff = false
            }
        }
    }

    func stage(file: ChangedFile) async {
        await mutateRepository { try await git.stage(path: file.filepath, in: $0) }
    }

    func unstage(file: ChangedFile) async {
        await mutateRepository { try await git.unstage(path: file.filepath, in: $0) }
    }

    func stageSelectedFile() async {
        guard let file = selectedFile else { return }
        await stage(file: file)
    }

    func unstageSelectedFile() async {
        guard let file = selectedFile else { return }
        await unstage(file: file)
    }

    func stageAll() async { await mutateRepository { try await git.stageAll(in: $0) } }
    func unstageAll() async { await mutateRepository { try await git.unstageAll(in: $0) } }

    func commit() async {
        guard let repoURL else { return }

        let summary = commitSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }

        let body = commitDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        isCommitting = true
        defer { isCommitting = false }

        do {
            guard try await git.hasStagedChanges(in: repoURL) else {
                presentError(.nothingToCommit)
                return
            }

            try await git.commit(
                summary: summary,
                body: body.isEmpty ? nil : body,
                author: auth.commitAuthor,
                in: repoURL
            )
            commitSummary = ""
            commitDescription = ""
            cancelDiffLoad()
            selectedFile = nil
            currentDiff = []
            await refreshStatus()
            await refreshHistory(for: historyBranchName)
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    private func performCheckout(_ branch: GitBranch) async {
        guard let repoURL else { return }

        do {
            try await git.checkout(branch: branch, in: repoURL)
            cancelDiffLoad()
            selectedFile = nil
            currentDiff = []
            historyBranchName = branch.localCheckoutName ?? branch.name
            await refreshStatus()
            await refreshBranches()
            await refreshHistory(for: historyBranchName)
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    private func checkoutRemoteOrLocalName(_ branchName: String) async {
        guard let repoURL else { return }

        do {
            try await git.checkout(branchName: branchName, in: repoURL)
            historyBranchName = branchName
            await refreshStatus()
            await refreshBranches()
            await refreshHistory(for: branchName)
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    private func sync(_ operation: (URL) async throws -> Void) async {
        guard let repoURL else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await operation(repoURL)
            await refreshStatus()
            await refreshHistory(for: historyBranchName)
            await refreshBranches()
            await refreshPullRequests()
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    private func mutateRepository(_ operation: (URL) async throws -> Void) async {
        guard let repoURL else { return }

        repoWatcher.pause()
        defer { repoWatcher.resume() }

        do {
            try await operation(repoURL)
            await refreshStatus()
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    private func clonedCatalogItems(
        apiFullNames: Set<String>,
        excludingPaths: Set<String>
    ) -> [RepositoryCatalogItem] {
        repoAccess.allGitHubLinks().compactMap { fullName, localURL in
            guard !apiFullNames.contains(fullName) else { return nil }

            let path = RepoAccessManager.normalizedPath(localURL)
            guard !excludingPaths.contains(path) else { return nil }

            let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
            return RepositoryCatalogItem(
                id: "cloned-\(fullName)",
                title: name,
                subtitle: fullName,
                fullName: fullName,
                localURL: localURL,
                htmlURL: URL(string: "https://github.com/\(fullName)"),
                source: .cloned
            )
        }
    }

    private func localOnlyCatalogItems(excludingPaths: Set<String> = []) -> [RepositoryCatalogItem] {
        repoAccess.recentRepositoryPathOrder().compactMap { path in
            guard !excludingPaths.contains(path) else { return nil }
            guard repoAccess.linkedFullName(forLocalPath: path) == nil else { return nil }

            let url = URL(fileURLWithPath: path, isDirectory: true)
            return RepositoryCatalogItem(
                id: "local-\(path)",
                title: url.lastPathComponent,
                subtitle: url.deletingLastPathComponent().path,
                fullName: nil,
                localURL: url,
                htmlURL: nil,
                source: .localOnly
            )
        }
    }

    private func sortCatalogByRecency(_ items: [RepositoryCatalogItem]) -> [RepositoryCatalogItem] {
        let recentOrder = repoAccess.recentRepositoryPathOrder()

        func recencyRank(for item: RepositoryCatalogItem) -> Int {
            guard let path = item.localURL.map({ RepoAccessManager.normalizedPath($0) }) else {
                return Int.max
            }
            return recentOrder.firstIndex(of: path) ?? Int.max
        }

        return items.sorted { lhs, rhs in
            let left = recencyRank(for: lhs)
            let right = recencyRank(for: rhs)
            if left != right { return left < right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func syncWithRemoteAfterOpen() async {
        guard let repoURL else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await git.fetch(in: repoURL)
            await refreshBranches()
            await refreshHistory(for: historyBranchName ?? currentBranch)
            await refreshStatus()
        } catch let error as GitError {
            if case .authenticationFailed = error {
                presentError(error)
            }
        } catch {
            // Network errors on open are non-fatal; local branches and history still work.
        }
    }

    private func matches(fullName: String, originURL: String) -> Bool {
        guard let parsed = GitRemoteURLParser.parseGitHubRepository(from: originURL) else {
            return false
        }
        return "\(parsed.owner)/\(parsed.name)" == fullName
    }

    private func cancelDiffLoad() {
        diffLoadTask?.cancel()
        diffLoadTask = nil
        isLoadingDiff = false
    }

    private func startWatchingRepository(at url: URL) {
        repoWatcher.start(watching: url) { [weak self] in
            guard let self else { return }
            Task { await self.refreshStatus() }
        }
    }
}

#if DEBUG
extension RepositoryStore {
    static var previewWithChanges: RepositoryStore {
        let store = RepositoryStore(auth: .previewSignedIn)
        store.repoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GitOriginPreview", isDirectory: true)
        store.currentBranch = "main"
        store.historyBranchName = "main"
        store.defaultBranchName = "main"
        store.githubRepository = GitHubRepository(owner: "octocat", name: "Hello-World", defaultBranch: "main")
        store.changedFiles = [
            ChangedFile(filepath: "Sources/App.swift", status: .modified, stagingState: .partiallyStaged),
            ChangedFile(filepath: "README.md", status: .modified, stagingState: .staged),
            ChangedFile(filepath: "notes.txt", status: .untracked, stagingState: .unstaged),
        ]
        store.selectedFile = store.changedFiles.first
        store.currentDiff = [
            DiffLine(id: 0, text: "@@ -1,3 +1,4 @@", type: .header),
            DiffLine(id: 1, text: " import SwiftUI", type: .context),
            DiffLine(id: 2, text: "+import Observation", type: .addition),
            DiffLine(id: 3, text: "-import Combine", type: .deletion),
        ]
        return store
    }
}
#endif
