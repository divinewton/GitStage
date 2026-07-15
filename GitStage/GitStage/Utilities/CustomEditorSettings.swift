//
//  CustomEditorSettings.swift
//  GitStage
//
//  Persists a user-chosen external editor application.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum CustomEditorSettings {
    private static let bookmarkKey = "customEditorBookmark"

    static var displayName: String? {
        customEditor()?.name
    }

    static func customEditor() -> ExternalEditor? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        return ExternalEditorDiscovery.editor(for: url)
    }

    static func setCustomEditor(applicationURL: URL) throws {
        guard let bookmark = try? applicationURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            throw CustomEditorError.bookmarkFailed
        }

        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    static func clearCustomEditor() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    @discardableResult
    static func promptForCustomEditor() -> ExternalEditor? {
        let panel = NSOpenPanel()
        panel.title = "Choose Editor Application"
        panel.message = "Select an app to open repositories and files in."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try setCustomEditor(applicationURL: url)
            return customEditor()
        } catch {
            return ExternalEditorDiscovery.editor(for: url)
        }
    }
}

enum CustomEditorError: LocalizedError {
    case bookmarkFailed

    var errorDescription: String? {
        switch self {
        case .bookmarkFailed:
            "Could not save access to the chosen editor."
        }
    }
}
