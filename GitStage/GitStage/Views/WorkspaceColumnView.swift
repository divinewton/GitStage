//
//  WorkspaceColumnView.swift
//  GitStage
//
//  Middle column with Changes / History segmented control and list content.
//

import SwiftUI

struct WorkspaceColumnView: View {
    @Bindable var store: RepositoryStore
    @Binding var mode: WorkspaceMode

    var body: some View {
        VStack(spacing: 0) {
            Picker("Page", selection: $mode) {
                ForEach(WorkspaceMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            Group {
                switch mode {
                case .changes:
                    ChangedFilesListView(store: store)
                case .history:
                    HistoryListView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.repoURL != nil, mode == .changes, !store.changedFiles.isEmpty {
                Divider()
                CommitBoxView(store: store)
            }
        }
        .navigationTitle(workspaceTitle)
        .onChange(of: store.preferredWorkspaceMode) { _, newMode in
            if let newMode {
                mode = newMode
                store.preferredWorkspaceMode = nil
            }
        }
        .onChange(of: store.currentBranch) { _, _ in
            Task { await store.refreshHistory(for: store.currentBranch) }
        }
        .task(id: mode) {
            guard store.repoURL != nil else { return }
            switch mode {
            case .history:
                await store.refreshHistory(for: store.historyBranchName ?? store.currentBranch)
            case .changes:
                break
            }
        }
    }

    private var workspaceTitle: String {
        if let name = store.githubRepository?.name {
            return name
        }
        if let repoURL = store.repoURL {
            return repoURL.lastPathComponent
        }
        return "No Repository"
    }
}
