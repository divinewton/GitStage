//
//  RepositoryStore.swift
//  GitOrigin
//

import Foundation
import Observation

@Observable
@MainActor
final class RepositoryStore {
    var repoURL: URL?
    var repoBookmark: Data?
    var changedFiles: [ChangedFile] = []
    var currentBranch: String?
    var selectedFile: ChangedFile?
    var currentDiff: [DiffLine] = []
    var isLoadingStatus = false
    var isLoadingDiff = false
    var isCommitting = false
    var lastError: GitError?

    private let git = GitExecutor.shared
    private let repoAccess = RepoAccessManager()

    func openRepositoryViaPanel() async {
        guard let url = repoAccess.promptForRepository() else { return }
        await openRepository(at: url)
    }

    func openRepository(at url: URL) async {
        lastError = nil

        do {
            // Create the bookmark before stopAccessing — revoking panel access first
            // prevents Git from reading `.git` and causes false "not a repository" errors.
            let bookmark = try repoAccess.createBookmark(for: url)
            let scopedURL = try repoAccess.resolveBookmark(bookmark)

            closeRepository()

            guard repoAccess.beginAccess(to: scopedURL) else {
                lastError = .accessDenied
                return
            }

            guard try await git.isInsideWorkTree(in: scopedURL) else {
                repoAccess.endAccess()
                lastError = .notARepository
                return
            }

            repoURL = scopedURL
            repoBookmark = bookmark
            repoAccess.saveRecentBookmark(bookmark)
            await refreshStatus()
        } catch let error as GitError {
            repoAccess.endAccess()
            lastError = error
        } catch {
            repoAccess.endAccess()
            lastError = .commandFailed(message: error.localizedDescription)
        }
    }

    func refreshStatus() async {
        guard let repoURL else { return }

        isLoadingStatus = true
        lastError = nil
        defer { isLoadingStatus = false }

        do {
            async let branch = git.currentBranch(in: repoURL)
            async let files = git.status(in: repoURL)

            let resolvedBranch = try await branch
            let resolvedFiles = try await files

            currentBranch = resolvedBranch
            changedFiles = resolvedFiles

            if let selected = selectedFile {
                selectedFile = resolvedFiles.first { $0.id == selected.id }
            }
        } catch let error as GitError {
            lastError = error
        } catch {
            lastError = .commandFailed(message: error.localizedDescription)
        }
    }

    func closeRepository() {
        selectedFile = nil
        changedFiles = []
        currentBranch = nil
        currentDiff = []
        repoURL = nil
        repoBookmark = nil
        repoAccess.endAccess()
    }
}
