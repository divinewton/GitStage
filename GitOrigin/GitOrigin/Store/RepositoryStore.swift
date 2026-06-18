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
    var currentDiff: [DiffHunk] = []
    var isLoadingStatus = false
    var isLoadingDiff = false
    var isCommitting = false
    var isSyncing = false
    var isLoadingHistory = false
    var isLoadingBranches = false
    var isLoadingPullRequests = false
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
    var commitCoAuthors = ""
    var isCommitFieldFocused = false

    var lastFetchedAt: Date?

    // MARK: - Repository sidebar sheets

    var activeRepositorySheet: RepositorySheet?
    var pendingRepositoryRemoval: RepositoryCatalogItem?
    var newRepoName = ""
    var newRepoDescription = ""
    var newRepoIsPrivate = false
    var newRepoDestinationURL: URL?
    var isCreatingRepository = false

    var cloneSourceMode: CloneSourceMode = .myRepositories
    var cloneCandidates: [GitHubRemoteRepository] = []
    var selectedCloneCandidateID: String?
    var publicCloneReference = ""
    var cloneDestinationURL: URL?
    var isLoadingCloneCandidates = false
    var isCloningRepository = false

    private let auth: GitHubAuthService
    private let git = GitExecutor.shared
    private let github = GitHubOAuthClient.shared
    private let repoAccess = RepoAccessManager()
    private let addedRegistry = AddedRepositoryRegistry()
    private let repoWatcher = GitRepoWatcher()
    private var diffLoadTask: Task<Void, Never>?
    private var isRefreshingStatus = false

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

    var remoteOnlyBranches: [GitBranch] {
        branches.remoteOnlyBranches()
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

    var preferredRemoteSyncAction: RemoteSyncAction {
        if upstreamStatus.behind > 0 { return .pull }
        if upstreamStatus.ahead > 0 { return .push }
        return .fetch
    }

    var lastFetchedDisplay: String {
        guard let lastFetchedAt else { return "Never fetched" }
        return "Last fetched \(Self.relativeFetchFormatter.localizedString(for: lastFetchedAt, relativeTo: Date()))"
    }

    private static let relativeFetchFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var newRepoDestinationPath: String {
        newRepoDestinationURL?.path ?? defaultCloneContainerPathDisplay
    }

    var cloneDestinationPath: String {
        cloneDestinationURL?.path ?? defaultCloneContainerPathDisplay
    }

    var canClone: Bool {
        if isCloningRepository { return false }
        if cloneSourceMode == .myRepositories {
            return selectedCloneCandidateID != nil
        }
        return !publicCloneReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAddedRepositories: Bool {
        !catalogItems.isEmpty
    }

    var currentRepositoryGitHubURL: URL? {
        currentCatalogItem?.htmlURL
            ?? githubRepository.flatMap {
                URL(string: "https://github.com/\($0.owner)/\($0.name)")
            }
    }

    private var currentCatalogItem: RepositoryCatalogItem? {
        guard let repoURL else { return nil }
        let path = RepoAccessManager.normalizedPath(repoURL)
        return catalogItems.first {
            RepoAccessManager.normalizedPath($0.localURL) == path
        }
    }

    private var defaultCloneContainerPathDisplay: String {
        CloneLocationSettings.defaultContainerURL()?.path ?? "Choose a folder"
    }

    func presentAddExistingSheet() {
        activeRepositorySheet = .addExisting
    }

    func presentCreateSheet() {
        activeRepositorySheet = .create
    }

    func presentCloneSheetIfReady() {
        if CloneLocationSettings.isConfigured {
            activeRepositorySheet = .clone
        } else {
            activeRepositorySheet = .setCloneLocation
        }
    }

    func prepareCreateRepositorySheet() {
        newRepoName = ""
        newRepoDescription = ""
        newRepoIsPrivate = false
        newRepoDestinationURL = CloneLocationSettings.defaultContainerURL()
    }

    func prepareCloneSheet() {
        cloneSourceMode = .myRepositories
        publicCloneReference = ""
        cloneDestinationURL = CloneLocationSettings.defaultContainerURL()
        selectedCloneCandidateID = cloneCandidates.first?.id
    }

    func chooseCreateRepositoryDestination() {
        guard let url = repoAccess.promptForDestinationDirectory() else { return }
        newRepoDestinationURL = url
    }

    func chooseCloneDestination() {
        guard let url = repoAccess.promptForDestinationDirectory() else { return }
        cloneDestinationURL = url
    }

    func configureDefaultCloneLocationFromPanel() async {
        guard let parent = repoAccess.promptForParentDirectory() else { return }
        guard parent.startAccessingSecurityScopedResource() else {
            presentError(.accessDenied)
            return
        }
        defer { parent.stopAccessingSecurityScopedResource() }

        do {
            try CloneLocationSettings.configure(parentDirectory: parent)
            cloneDestinationURL = CloneLocationSettings.defaultContainerURL()
            newRepoDestinationURL = cloneDestinationURL
        } catch {
            presentAlert(title: "Clone Location", message: error.localizedDescription)
        }
    }

    func preloadRepositorySheetData() async {
        await loadCloneCandidatesIfNeeded()
    }

    func loadCloneCandidatesIfNeeded() async {
        guard cloneCandidates.isEmpty else { return }
        guard let token = GitHubKeychain.loadAccessToken() else { return }

        isLoadingCloneCandidates = true
        defer { isLoadingCloneCandidates = false }

        do {
            cloneCandidates = try await github.fetchUserRepositories(accessToken: token)
            selectedCloneCandidateID = cloneCandidates.first?.id
        } catch {
            presentAlert(title: "GitHub Repositories", message: error.localizedDescription)
        }
    }

    func addExistingRepositoryFromPanel() async {
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

            activeRepositorySheet = nil
            await registerAndOpenRepository(at: accessed)
        } catch let error as GitError {
            repoAccess.endAccess()
            presentError(error)
        } catch {
            repoAccess.endAccess()
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    func createRepositoryOnGitHub() async {
        guard let token = GitHubKeychain.loadAccessToken() else { return }

        let name = newRepoName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        guard let container = newRepoDestinationURL ?? CloneLocationSettings.defaultContainerURL() else {
            activeRepositorySheet = .setCloneLocation
            return
        }

        isCreatingRepository = true
        defer { isCreatingRepository = false }

        do {
            let remote = try await github.createRepository(
                name: name,
                description: newRepoDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                isPrivate: newRepoIsPrivate,
                accessToken: token
            )

            guard container.startAccessingSecurityScopedResource() else {
                presentError(.accessDenied)
                return
            }
            defer { container.stopAccessingSecurityScopedResource() }

            let destination = CloneLocationSettings.destinationURL(forRepositoryNamed: remote.name, in: container)
            try await git.clone(from: remote.cloneURL.absoluteString, into: remote.name, parentDirectory: container)

            activeRepositorySheet = nil
            await registerAndOpenRepository(at: destination, remote: remote)
        } catch let error as GitHubOAuthClientError {
            presentAlert(title: "Create Repository", message: error.localizedDescription ?? "Request failed.")
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    func cloneSelectedRepository() async {
        isCloningRepository = true
        defer { isCloningRepository = false }

        do {
            let remote: GitHubRemoteRepository
            if cloneSourceMode == .myRepositories {
                guard let id = selectedCloneCandidateID,
                      let selected = cloneCandidates.first(where: { $0.id == id }) else {
                    return
                }
                remote = selected
            } else {
                let reference = publicCloneReference.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsed = GitRemoteURLParser.parseGitHubReference(from: reference) else {
                    presentAlert(title: "Invalid Repository", message: "Enter owner/repo or a github.com URL.")
                    return
                }
                let token = GitHubKeychain.loadAccessToken()
                remote = try await github.fetchRepository(
                    owner: parsed.owner,
                    repo: parsed.name,
                    accessToken: token
                )
            }

            guard let container = cloneDestinationURL ?? CloneLocationSettings.defaultContainerURL() else {
                activeRepositorySheet = .setCloneLocation
                return
            }

            guard container.startAccessingSecurityScopedResource() else {
                presentError(.accessDenied)
                return
            }
            defer { container.stopAccessingSecurityScopedResource() }

            let destination = CloneLocationSettings.destinationURL(forRepositoryNamed: remote.name, in: container)
            if FileManager.default.fileExists(atPath: destination.path) {
                presentAlert(title: "Already Exists", message: "A folder named “\(remote.name)” already exists at the clone location.")
                return
            }

            try await git.clone(from: remote.cloneURL.absoluteString, into: remote.name, parentDirectory: container)
            activeRepositorySheet = nil
            await registerAndOpenRepository(at: destination, remote: remote)
        } catch let error as GitHubOAuthClientError {
            presentAlert(title: "Clone Repository", message: error.localizedDescription ?? "Request failed.")
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
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

    func refreshRepositoryCatalog() {
        catalogItems = addedRegistry.catalogItems()
    }

    func openCatalogItem(_ item: RepositoryCatalogItem) async {
        await openRepository(at: item.localURL)
    }

    func openCatalogItemOnGitHub(_ item: RepositoryCatalogItem) {
        guard let htmlURL = item.htmlURL else { return }
        NSWorkspace.shared.open(htmlURL)
    }

    func revealCatalogItemInFinder(_ item: RepositoryCatalogItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.localURL])
    }

    func openCatalogItemInEditor(_ item: RepositoryCatalogItem, editor: ExternalEditor) {
        PreferredEditorSettings.saveLastUsedEditor(editor)
        ExternalEditorDiscovery.open(item.localURL, with: editor)
    }

    func openChangedFileInEditor(_ file: ChangedFile, editor: ExternalEditor) {
        guard let repoURL else { return }
        PreferredEditorSettings.saveLastUsedEditor(editor)
        let fileURL = repoURL.appendingPathComponent(file.filepath)
        ExternalEditorDiscovery.openFile(fileURL, with: editor)
    }

    func openCurrentRepositoryInFinder() {
        guard let repoURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([repoURL])
    }

    func openCurrentRepositoryOnGitHub() {
        guard let htmlURL = currentRepositoryGitHubURL else { return }
        NSWorkspace.shared.open(htmlURL)
    }

    func openCurrentRepositoryInEditor(editor: ExternalEditor) {
        guard let repoURL else { return }
        PreferredEditorSettings.saveLastUsedEditor(editor)
        ExternalEditorDiscovery.open(repoURL, with: editor)
    }

    func openCurrentRepositoryInPreferredEditor() {
        guard repoURL != nil, let editor = PreferredEditorSettings.preferredEditor() else { return }
        openCurrentRepositoryInEditor(editor: editor)
    }

    var preferredEditorDisplayName: String {
        PreferredEditorSettings.preferredEditor()?.name ?? "Editor"
    }

    var canOpenCurrentRepositoryOnGitHub: Bool {
        currentRepositoryGitHubURL != nil
    }

    func requestRemoveAddedRepository(_ item: RepositoryCatalogItem) {
        pendingRepositoryRemoval = item
    }

    func cancelRemoveAddedRepository() {
        pendingRepositoryRemoval = nil
    }

    func confirmRemoveAddedRepository(moveToTrash: Bool) {
        guard let item = pendingRepositoryRemoval else { return }
        pendingRepositoryRemoval = nil

        if moveToTrash {
            trashRepositoryFolder(at: item.localURL)
        }

        if let repoURL,
           RepoAccessManager.normalizedPath(item.localURL) == RepoAccessManager.normalizedPath(repoURL) {
            closeRepository()
        }

        addedRegistry.remove(id: item.id)
        refreshRepositoryCatalog()
    }

    private func trashRepositoryFolder(at url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            presentAlert(title: "Move to Trash", message: "GitOrigin could not access the repository folder.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            presentAlert(title: "Move to Trash", message: error.localizedDescription)
        }
    }

    private func registerAndOpenRepository(
        at url: URL,
        remote: GitHubRemoteRepository? = nil
    ) async {
        let metadata = await repositoryMetadata(for: url, remote: remote)
        addedRegistry.register(
            localURL: url,
            owner: metadata.owner,
            name: metadata.name,
            fullName: metadata.fullName,
            htmlURL: metadata.htmlURL
        )
        refreshRepositoryCatalog()
        await openRepository(at: url)
    }

    private func repositoryMetadata(
        for url: URL,
        remote: GitHubRemoteRepository?
    ) async -> (owner: String, name: String, fullName: String?, htmlURL: URL?) {
        if let remote {
            return (remote.owner, remote.name, remote.fullName, remote.htmlURL)
        }

        if let origin = try? await git.originURL(in: url),
           let parsed = GitRemoteURLParser.parseGitHubRepository(from: origin) {
            let fullName = "\(parsed.owner)/\(parsed.name)"
            return (
                parsed.owner,
                parsed.name,
                fullName,
                URL(string: "https://github.com/\(fullName)")
            )
        }

        return ("Local", url.lastPathComponent, nil, nil)
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

            historyBranchName = nil
            startWatchingRepository(at: workingURL)
            await refreshStatus(userInitiated: true)
            await refreshBranches()
            await refreshHistory(for: currentBranch)
            await syncWithRemoteAfterOpen()
            await refreshRepositoryMetadata()
            await refreshPullRequests()
            refreshRepositoryCatalog()
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
        commitCoAuthors = ""
        lastFetchedAt = nil
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

            if let token = GitHubKeychain.loadAccessToken() {
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
        guard let token = GitHubKeychain.loadAccessToken() else {
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

    func fetch() async {
        await sync(updatesFetchTimestamp: true) { try await git.fetch(in: $0) }
    }

    func pull() async {
        await sync(updatesFetchTimestamp: true) { try await git.pull(in: $0) }
    }

    func push() async {
        await sync(updatesFetchTimestamp: false) { url in
            if upstreamStatus.upstreamName == nil, let branch = currentBranch {
                try await git.push(setUpstream: branch, in: url)
            } else {
                try await git.push(in: url)
            }
        }
    }

    func performPreferredRemoteSync() async {
        switch preferredRemoteSyncAction {
        case .fetch:
            await fetch()
        case .pull:
            await pull()
        case .push:
            await push()
        }
    }

    func selectFile(_ file: ChangedFile?) {
        if selectedFile?.id == file?.id { return }

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
        if selectedFile?.id == id { return }
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
        await mutateStaging { try await git.stage(path: file.filepath, in: $0) }
    }

    func unstage(file: ChangedFile) async {
        await mutateStaging { try await git.unstage(path: file.filepath, in: $0) }
    }

    func stageAll() async { await mutateStaging { try await git.stageAll(in: $0) } }
    func unstageAll() async { await mutateStaging { try await git.unstageAll(in: $0) } }

    func discardChanges(for file: ChangedFile) async {
        let discardedFileID = file.id
        await mutateStaging { try await git.discardChanges(for: file, in: $0) }

        if selectedFile?.id == discardedFileID,
           !changedFiles.contains(where: { $0.id == discardedFileID }) {
            cancelDiffLoad()
            selectedFile = nil
            currentDiff = []
        }
    }

    func commit() async {
        guard let repoURL else { return }

        let summary = commitSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }

        let body = commitDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullBody = Self.commitBody(description: body, coAuthors: commitCoAuthors)

        isCommitting = true
        defer { isCommitting = false }

        do {
            guard try await git.hasStagedChanges(in: repoURL) else {
                presentError(.nothingToCommit)
                return
            }

            try await git.commit(
                summary: summary,
                body: fullBody,
                author: auth.commitAuthor,
                in: repoURL
            )
            commitSummary = ""
            commitDescription = ""
            commitCoAuthors = ""
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

    private func sync(updatesFetchTimestamp: Bool, _ operation: (URL) async throws -> Void) async {
        guard let repoURL else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await operation(repoURL)
            if updatesFetchTimestamp {
                lastFetchedAt = Date()
            }
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

    private static func commitBody(description: String, coAuthors: String) -> String? {
        let coAuthorLines = coAuthors
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                line.hasPrefix("Co-authored-by:") ? line : "Co-authored-by: \(line)"
            }

        switch (description.isEmpty, coAuthorLines.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return description
        case (true, false):
            return coAuthorLines.joined(separator: "\n")
        case (false, false):
            return description + "\n\n" + coAuthorLines.joined(separator: "\n")
        }
    }

    private func mutateStaging(_ operation: (URL) async throws -> Void) async {
        guard let repoURL else { return }

        repoWatcher.pause()
        defer { repoWatcher.resume() }

        do {
            try await operation(repoURL)
            await refreshChangedFilesOnly()
        } catch let error as GitError {
            presentError(error)
        } catch {
            presentError(.commandFailed(message: error.localizedDescription))
        }
    }

    private func refreshChangedFilesOnly() async {
        guard let repoURL else { return }

        let selectedID = selectedFile?.id

        do {
            let resolvedFiles = try await git.status(in: repoURL)
            changedFiles = resolvedFiles

            if let selectedID,
               let file = resolvedFiles.first(where: { $0.id == selectedID }) {
                selectedFile = file
            } else if selectedID != nil {
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

    private func syncWithRemoteAfterOpen() async {
        guard let repoURL else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            try await git.fetch(in: repoURL)
            lastFetchedAt = Date()
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
            DiffHunk(
                id: 0,
                header: "@@ -1,3 +1,4 @@",
                lines: [
                    DiffLine(id: 0, text: "import SwiftUI", type: .context, oldLineNumber: 1, newLineNumber: 1, noNewlineAtEnd: false),
                    DiffLine(id: 1, text: "import Observation", type: .addition, oldLineNumber: nil, newLineNumber: 2, noNewlineAtEnd: false),
                    DiffLine(id: 2, text: "import Combine", type: .deletion, oldLineNumber: 2, newLineNumber: nil, noNewlineAtEnd: false),
                ]
            ),
        ]
        store.catalogItems = [
            RepositoryCatalogItem(
                id: "octocat/Hello-World",
                owner: "octocat",
                name: "Hello-World",
                fullName: "octocat/Hello-World",
                localURL: store.repoURL!,
                htmlURL: URL(string: "https://github.com/octocat/Hello-World")
            ),
        ]
        return store
    }

    static var previewClean: RepositoryStore {
        let store = RepositoryStore(auth: .previewSignedIn)
        store.repoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GitOriginPreviewClean", isDirectory: true)
        store.currentBranch = "main"
        store.historyBranchName = "main"
        store.defaultBranchName = "main"
        store.githubRepository = GitHubRepository(owner: "octocat", name: "Hello-World", defaultBranch: "main")
        store.changedFiles = []
        store.catalogItems = [
            RepositoryCatalogItem(
                id: "octocat/Hello-World",
                owner: "octocat",
                name: "Hello-World",
                fullName: "octocat/Hello-World",
                localURL: store.repoURL!,
                htmlURL: URL(string: "https://github.com/octocat/Hello-World")
            ),
        ]
        return store
    }
}
#endif
