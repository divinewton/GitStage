//
//  PreferredEditorSettings.swift
//  GitStage
//
//  Remembers the last editor used and resolves the default open target.
//

import Foundation

enum PreferredEditorSettings {
    private static let lastUsedBookmarkKey = "lastUsedEditorBookmark"
    private static let defaultEditorBundleID = "com.microsoft.VSCode"

    static func saveLastUsedEditor(_ editor: ExternalEditor) {
        guard let bookmark = try? editor.applicationURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        UserDefaults.standard.set(bookmark, forKey: lastUsedBookmarkKey)
    }

    static func preferredEditor() -> ExternalEditor? {
        if let lastUsed = lastUsedEditor() {
            return lastUsed
        }

        if let vscode = editorMatchingBundleID(defaultEditorBundleID) {
            return vscode
        }

        return ExternalEditorDiscovery.availableEditors().first
    }

    private static func lastUsedEditor() -> ExternalEditor? {
        guard let data = UserDefaults.standard.data(forKey: lastUsedBookmarkKey) else { return nil }
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

    private static func editorMatchingBundleID(_ bundleID: String) -> ExternalEditor? {
        ExternalEditorDiscovery.availableEditors().first { $0.id == bundleID }
    }
}
