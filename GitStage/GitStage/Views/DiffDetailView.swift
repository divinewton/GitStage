//
//  DiffDetailView.swift
//  GitStage
//
//  Detail column header and wrapper around DiffView for the selected file.
//

import SwiftUI

struct DiffDetailView: View {
    @Bindable var store: RepositoryStore

    var body: some View {
        Group {
            if store.repoURL != nil, store.changedFiles.isEmpty {
                RepositoryShortcutsView(store: store)
            } else if store.selectedFile == nil {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a changed file to preview its diff.")
                )
            } else {
                VStack(spacing: 0) {
                    fileHeader
                    Divider()
                    DiffView(hunks: store.currentDiff, isLoading: store.isLoadingDiff)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(detailTitle)
    }

    private var detailTitle: String {
        if store.repoURL != nil, store.changedFiles.isEmpty {
            if let name = store.githubRepository?.name {
                return name
            }
            if let repoURL = store.repoURL {
                return repoURL.lastPathComponent
            }
        }
        return store.selectedFile?.filepath ?? "Diff"
    }

    @ViewBuilder
    private var fileHeader: some View {
        if let file = store.selectedFile {
            HStack(spacing: 12) {
                ChangedFileBadge(file: file)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filepath)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusDescription(for: file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoadingDiff {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.25))
        }
    }

    private func statusDescription(for file: ChangedFile) -> String {
        let status = switch file.status {
        case .modified: "Modified"
        case .added: "Added"
        case .deleted: "Deleted"
        case .untracked: "Untracked"
        case .renamed: "Renamed"
        }

        let staging = switch file.stagingState {
        case .staged: "Staged"
        case .unstaged: "Unstaged"
        case .partiallyStaged: "Partially staged"
        }

        return "\(status) · \(staging)"
    }
}
