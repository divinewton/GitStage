//
//  RepoAccessManager.swift
//  GitOrigin
//

import AppKit
import Foundation

@MainActor
final class RepoAccessManager {
    private static let recentBookmarkKey = "recentRepositoryBookmark"

    private var accessedURL: URL?

    func promptForRepository() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Git Repository"
        panel.message = "Choose a folder containing a Git repository."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return url
    }

    @discardableResult
    func beginAccess(to url: URL) -> Bool {
        endAccess()
        guard url.startAccessingSecurityScopedResource() else {
            return false
        }
        accessedURL = url
        return true
    }

    func endAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            let refreshed = try createBookmark(for: url)
            saveRecentBookmark(refreshed)
        }

        return url
    }

    func saveRecentBookmark(_ data: Data) {
        UserDefaults.standard.set(data, forKey: Self.recentBookmarkKey)
    }

    func loadRecentBookmark() -> Data? {
        UserDefaults.standard.data(forKey: Self.recentBookmarkKey)
    }
}
