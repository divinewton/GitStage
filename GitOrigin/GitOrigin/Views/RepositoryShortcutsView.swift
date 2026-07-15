//
//  RepositoryShortcutsView.swift
//  GitOrigin
//
//  Right-column shortcuts when the working tree has no local changes.
//

import SwiftUI

struct RepositoryShortcutsView: View {
    @Bindable var store: RepositoryStore

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text("No local changes")
                    .font(.title2.weight(.semibold))

                Text("Working tree is clean on \(store.currentBranch ?? "this branch").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                shortcutButton(
                    title: "Reveal in Finder",
                    systemImage: "folder",
                    shortcutLabel: RepositoryCommandShortcuts.revealInFinderLabel,
                    shortcut: RepositoryCommandShortcuts.revealInFinder
                ) {
                    store.openCurrentRepositoryInFinder()
                }

                if store.canOpenCurrentRepositoryOnGitHub {
                    shortcutButton(
                        title: "Open on GitHub",
                        systemImage: "link",
                        shortcutLabel: RepositoryCommandShortcuts.openOnGitHubLabel,
                        shortcut: RepositoryCommandShortcuts.openOnGitHub
                    ) {
                        store.openCurrentRepositoryOnGitHub()
                    }
                }

                shortcutButton(
                    title: "Open in \(store.preferredEditorDisplayName)",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    shortcutLabel: RepositoryCommandShortcuts.openInEditorLabel,
                    shortcut: RepositoryCommandShortcuts.openInEditor
                ) {
                    store.openCurrentRepositoryInPreferredEditor()
                }

                EditorOpenMenu(open: { editor in
                    store.openCurrentRepositoryInEditor(editor: editor)
                }) {
                    Text("Choose Another Editor…")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func shortcutButton(
        title: String,
        systemImage: String,
        shortcutLabel: String,
        shortcut: KeyboardShortcut,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(shortcutLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(width: 280)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .keyboardShortcut(shortcut)
    }
}

#Preview {
    RepositoryShortcutsView(store: .previewClean)
        .frame(width: 420, height: 480)
}
