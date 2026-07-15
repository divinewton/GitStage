//
//  CloneLocationSettings.swift
//  GitStage
//
//  Default folder for cloned repositories (`…/GitStage/<repo-name>`).
//

import Foundation

@MainActor
enum CloneLocationSettings {
    private static let configuredKey = "cloneRootConfigured"
    private static let cloneRootBookmarkKey = "cloneRootBookmark"

    static var isConfigured: Bool {
        UserDefaults.standard.bool(forKey: configuredKey)
    }

    static var displayPath: String {
        defaultContainerURL()?.path ?? "Not set"
    }

    /// Security-scoped URL to the `GitStage` folder inside the user-chosen parent directory.
    static func defaultContainerURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: cloneRootBookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return url.standardizedFileURL
    }

    static func configure(parentDirectory: URL) throws {
        let gitStage = parentDirectory
            .standardizedFileURL
            .appendingPathComponent("GitStage", isDirectory: true)

        try FileManager.default.createDirectory(at: gitStage, withIntermediateDirectories: true)

        guard let bookmark = try? gitStage.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            throw CloneLocationError.bookmarkFailed
        }

        UserDefaults.standard.set(bookmark, forKey: cloneRootBookmarkKey)
        UserDefaults.standard.set(true, forKey: configuredKey)
    }

    static func destinationURL(forRepositoryNamed name: String, in container: URL) -> URL {
        container.appendingPathComponent(name, isDirectory: true)
    }
}

enum CloneLocationError: LocalizedError {
    case bookmarkFailed

    var errorDescription: String? {
        switch self {
        case .bookmarkFailed:
            "Could not save access to the clone folder."
        }
    }
}
