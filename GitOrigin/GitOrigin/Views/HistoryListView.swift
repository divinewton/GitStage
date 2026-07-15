//
//  HistoryListView.swift
//  GitOrigin
//
//  Commit log for the current (or selected) branch.
//

import SwiftUI

struct HistoryListView: View {
    @Bindable var store: RepositoryStore

    var body: some View {
        if store.repoURL == nil {
            ContentUnavailableView(
                "No Repository",
                systemImage: "folder",
                description: Text("Choose a repository to view commit history.")
            )
        } else if store.isLoadingHistory && store.commits.isEmpty {
            ProgressView("Loading history…")
        } else if store.commits.isEmpty {
            ContentUnavailableView(
                "No Commits",
                systemImage: "clock",
                description: Text("No commits on \(store.historyDisplayBranch).")
            )
        } else {
            List(store.commits) { commit in
                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.subject)
                        .lineLimit(2)
                    Text(commit.hash)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}
