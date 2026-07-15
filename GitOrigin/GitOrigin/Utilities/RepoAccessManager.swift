//
//  RepoAccessManager.swift
//  GitOrigin
//
//  NSOpenPanel for choosing a repo folder and security-scoped bookmark persistence.
//

import AppKit
import Foundation

@MainActor
final class RepoAccessManager {
    private static let recentBookmarksKey = "recentRepositoryBookmarks"
    private static let maxRecentCount = 12

    /// The repository URL that currently holds an active security-scoped grant.
    private var activeURL: URL?

    /// Presents a folder picker. The returned URL must be passed to `beginAccess(to:)`.
    func promptForRepository() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Git Repository"
        panel.message = "Choose a folder that contains a Git repository."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return url.standardizedFileURL
    }

    /// Chooses a parent folder; used for the default clone location setup.
    func promptForParentDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Clone Location"
        panel.message = "GitOrigin will create a GitOrigin folder here for your clones."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return url.standardizedFileURL
    }

    /// Chooses a folder to store a newly created repository.
    func promptForDestinationDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder"
        panel.message = "Select where this repository should live on your Mac."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return url.standardizedFileURL
    }

    /// Starts security-scoped access for `url`. Returns nil if the app cannot read the folder.
    func beginAccess(to url: URL) -> URL? {
        endAccess()

        let targetPath = Self.normalizedPath(url)

        if let bookmarkURL = resolveSavedBookmark(matchingPath: targetPath) {
            activeURL = bookmarkURL
            return bookmarkURL
        }

        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }

        activeURL = url.standardizedFileURL
        return activeURL
    }

    /// Releases the active security-scoped grant when closing a repository.
    func endAccess() {
        guard let activeURL else { return }
        activeURL.stopAccessingSecurityScopedResource()
        self.activeURL = nil
    }

    /// Persists a security-scoped bookmark so the repo can be reopened after relaunch.
    func addRecentRepository(_ url: URL) {
        guard let bookmark = makeBookmark(for: url) else { return }

        var bookmarks = loadRecentBookmarks()
        let targetPath = Self.normalizedPath(url)
        bookmarks.removeAll { existing in
            guard let resolved = resolveBookmarkData(existing) else { return false }
            return Self.normalizedPath(resolved) == targetPath
        }

        bookmarks.insert(bookmark, at: 0)
        if bookmarks.count > Self.maxRecentCount {
            bookmarks = Array(bookmarks.prefix(Self.maxRecentCount))
        }

        UserDefaults.standard.set(bookmarks, forKey: Self.recentBookmarksKey)
    }

    /// Recent repository paths, most recently opened first (bookmark paths only).
    func recentRepositoryPathOrder() -> [String] {
        loadRecentBookmarks().compactMap { data in
            resolveBookmarkData(data).map { Self.normalizedPath($0) }
        }
    }

    /// Recent repository folders for menus (does not start security-scoped access).
    func recentRepositories() -> [URL] {
        recentRepositoryPathOrder().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Opens the most recently used repository bookmark, if still available.
    func restoreRecentRepository() -> URL? {
        for data in loadRecentBookmarks() {
            guard let url = resolveBookmarkData(data) else { continue }
            if let accessed = beginAccess(to: url) {
                guard FileManager.default.fileExists(atPath: accessed.path) else {
                    endAccess()
                    continue
                }
                return accessed
            }
        }
        return nil
    }

    func canWriteToGitDirectory(at repoURL: URL) -> Bool {
        let gitDirectory = repoURL.appendingPathComponent(".git", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        let probeURL = gitDirectory.appendingPathComponent(".gitorigin-write-probe")
        do {
            try Data().write(to: probeURL, options: .atomic)
            try FileManager.default.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Bookmarks

    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func loadRecentBookmarks() -> [Data] {
        UserDefaults.standard.array(forKey: Self.recentBookmarksKey) as? [Data] ?? []
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolveSavedBookmark(matchingPath targetPath: String) -> URL? {
        for data in loadRecentBookmarks() {
            if let resolved = resolveBookmarkData(data),
               Self.normalizedPath(resolved) == targetPath,
               startAccess(resolved) {
                return resolved
            }
        }

        return nil
    }

    private func resolveBookmarkData(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func startAccess(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }
}
