//
//  ContentView.swift
//  GitOrigin
//
//  Signed-in three-column shell: repo sidebar, workspace column, diff + commit detail.
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: RepositoryStore
    @State private var workspaceMode: WorkspaceMode = .changes
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RepositorySidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            WorkspaceColumnView(store: store, mode: $workspaceMode)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            DiffDetailView(store: store)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                BranchSwitcherMenu(store: store)
            }

            ToolbarItem(placement: .primaryAction) {
                RemoteSyncToolbarItem(store: store)
            }
        }
        .task {
            guard store.repoURL != nil else { return }
            await store.refreshBranches()
        }
    }
}

#Preview("Empty") {
    ContentView(store: RepositoryStore(auth: .previewSignedIn))
}

#Preview("With Changes") {
    ContentView(store: .previewWithChanges)
}
