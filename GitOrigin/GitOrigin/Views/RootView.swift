//
//  RootView.swift
//  GitOrigin
//
//  Routes between session restore, sign-in gate, welcome, and the main workspace.
//

import SwiftUI

struct RootView: View {
    @Bindable var store: RepositoryStore
    @Bindable var auth: GitHubAuthService

    @State private var showGitInstallPrompt = false

    var body: some View {
        Group {
            if auth.isRestoringSession {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.isSignedIn {
                if store.hasAddedRepositories {
                    ContentView(store: store)
                } else {
                    WelcomeEmptyView(store: store)
                }
            } else {
                GitHubSignInGateView(auth: auth)
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .repositoryFlowModifiers(store: store)
        .task {
            if !GitInstallSupport.isGitAvailable {
                showGitInstallPrompt = true
            }

            await auth.restoreSessionIfAvailable()
            if auth.isSignedIn {
                store.refreshRepositoryCatalog()
                await store.preloadRepositorySheetData()
                if store.hasAddedRepositories {
                    await store.restoreRecentRepositoryIfAvailable()
                }
            }
        }
        .onChange(of: auth.isSignedIn) { wasSignedIn, isSignedIn in
            if isSignedIn, !wasSignedIn {
                store.refreshRepositoryCatalog()
                Task {
                    await store.preloadRepositorySheetData()
                    if store.hasAddedRepositories {
                        await store.restoreRecentRepositoryIfAvailable()
                    }
                }
            } else if !isSignedIn {
                store.closeRepository()
            }
        }
        .alert("Git Is Required", isPresented: $showGitInstallPrompt) {
            Button("Install Command Line Tools") {
                GitInstallSupport.installCommandLineTools()
            }
            Button("Download Git") {
                GitInstallSupport.openGitDownloadPage()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("GitOrigin uses Git on your Mac to work with repositories. Install Apple’s Command Line Tools or Git from git-scm.com, then relaunch GitOrigin.")
        }
    }
}
