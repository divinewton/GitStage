//
//  ContentView.swift
//  GitOrigin
//
//  Signed-in three-column shell: repo sidebar, workspace column, diff + commit detail.
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: RepositoryStore
    @Bindable var auth: GitHubAuthService
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
            VStack(spacing: 0) {
                DiffDetailView(store: store)
                if store.repoURL != nil {
                    Divider()
                    CommitBoxView(store: store)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                BranchSwitcherMenu(store: store)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if store.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await store.push() }
                    } label: {
                        Label("Push", systemImage: "arrow.up.circle")
                    }
                    .disabled(store.repoURL == nil || store.isSyncing)
                }

                if let session = auth.session {
                    Menu {
                        Button("Sign Out", role: .destructive) {
                            auth.signOut()
                        }
                    } label: {
                        Label(session.login, systemImage: "person.crop.circle")
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .sheet(isPresented: $store.showCreateBranchSheet) {
            CreateBranchSheet(store: store)
        }
        .alert(item: $store.presentedAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(
            "Uncommitted Changes",
            isPresented: $store.showDirtyCheckoutConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                store.cancelCheckout()
            }
            Button("Checkout Anyway", role: .destructive) {
                Task { await store.confirmCheckout() }
            }
        } message: {
            if let branch = store.pendingCheckoutBranch {
                Text("You have uncommitted changes. Checking out “\(branch.name)” may fail or carry changes over.")
            }
        }
        .task {
            guard store.repoURL != nil else { return }
            await store.refreshBranches()
        }
    }

    private func toggleRepositorySidebar() {
        columnVisibility = columnVisibility == .all ? .doubleColumn : .all
    }
}

#Preview("Empty") {
    ContentView(store: RepositoryStore(auth: .previewSignedIn), auth: .previewSignedIn)
}

#Preview("With Changes") {
    ContentView(store: .previewWithChanges, auth: .previewSignedIn)
}
