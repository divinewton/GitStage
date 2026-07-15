//
//  RepositoryCommandShortcuts.swift
//  GitOrigin
//
//  Shared keyboard shortcuts for repository actions.
//

import SwiftUI

enum RepositoryCommandShortcuts {
    static let revealInFinder = KeyboardShortcut("f", modifiers: [.command, .option])
    static let openInEditor = KeyboardShortcut("e", modifiers: [.command, .option])
    static let openOnGitHub = KeyboardShortcut("g", modifiers: [.command, .option])

    static let revealInFinderLabel = "⌘⌥F"
    static let openInEditorLabel = "⌘⌥E"
    static let openOnGitHubLabel = "⌘⌥G"
}
