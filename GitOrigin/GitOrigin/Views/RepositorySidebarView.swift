//
//  RepositorySidebarView.swift
//  GitOrigin
//
//  Repository list from GitHub (with optional local links) plus local-only folders.
//

import AppKit
import SwiftUI

struct RepositorySidebarView: View {
    @Bindable var store: RepositoryStore

    @State private var isRecentExpanded = true
    @State private var isClonedExpanded = true
    @State private var isGitHubExpanded = true
    @State private var isLocalOnlyExpanded = true

    var body: some View {
        List {
            Section {
                Button {
                    Task { await store.openRepositoryViaPanel() }
                } label: {
                    Label("Open Folder…", systemImage: "folder.badge.plus")
                }

                Button {
                    Task { await store.refreshRepositoryCatalog() }
                } label: {
                    Label("Refresh List", systemImage: "arrow.clockwise")
                }
            }

            if !recentItems.isEmpty {
                Section(isExpanded: $isRecentExpanded) {
                    ForEach(recentItems) { item in
                        repositoryRow(item)
                    }
                } header: {
                    Text("Recent")
                }
            }

            if !remainingClonedItems.isEmpty {
                Section(isExpanded: $isClonedExpanded) {
                    ForEach(remainingClonedItems) { item in
                        repositoryRow(item)
                    }
                } header: {
                    Text("Cloned")
                }
            }

            if !remainingGitHubItems.isEmpty {
                Section(isExpanded: $isGitHubExpanded) {
                    ForEach(remainingGitHubItems) { item in
                        repositoryRow(item)
                    }
                } header: {
                    Text("GitHub")
                }
            }

            if !remainingLocalOnlyItems.isEmpty {
                Section(isExpanded: $isLocalOnlyExpanded) {
                    ForEach(remainingLocalOnlyItems) { item in
                        repositoryRow(item)
                    }
                } header: {
                    Text("Local Only")
                }
            }

            if store.isLoadingCatalog && store.catalogItems.isEmpty {
                Section {
                    ProgressView("Loading repositories…")
                }
            } else if store.catalogItems.isEmpty {
                Section {
                    Text("Sign in to list GitHub repositories, or use Open Folder to choose a local clone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Repositories")
    }

    private var recentItemIDs: Set<String> {
        Set(recentItems.map(\.id))
    }

    private var recentItems: [RepositoryCatalogItem] {
        let order = store.recentRepositoryPathOrder
        var seen = Set<String>()

        return order.compactMap { path in
            guard let item = store.catalogItems.first(where: { item in
                guard let localURL = item.localURL else { return false }
                return RepoAccessManager.normalizedPath(localURL) == path
            }) else {
                return nil
            }
            guard seen.insert(item.id).inserted else { return nil }
            return item
        }
    }

    private var remainingClonedItems: [RepositoryCatalogItem] {
        store.catalogItems.filter { $0.source == .cloned && !recentItemIDs.contains($0.id) }
    }

    private var remainingGitHubItems: [RepositoryCatalogItem] {
        store.catalogItems.filter { $0.source == .github && !recentItemIDs.contains($0.id) }
    }

    private var remainingLocalOnlyItems: [RepositoryCatalogItem] {
        store.catalogItems.filter { $0.source == .localOnly && !recentItemIDs.contains($0.id) }
    }

    @ViewBuilder
    private func repositoryRow(_ item: RepositoryCatalogItem) -> some View {
        HStack(spacing: 8) {
            availabilityBadge(for: item)
                .frame(width: 18, alignment: .center)

            Button {
                Task { await store.openCatalogItem(item) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .fontWeight(isSelected(item) ? .semibold : .regular)
                    Text(rowSubtitle(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                repositoryMenu(for: item)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Repository actions")
        }
        .listRowBackground(isSelected(item) ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    @ViewBuilder
    private func repositoryMenu(for item: RepositoryCatalogItem) -> some View {
        if item.isAvailableLocally {
            Button("Open") {
                Task { await store.openCatalogItem(item) }
            }
            Button("Reveal in Finder") {
                store.revealCatalogItemInFinder(item)
            }
        }

        if item.source == .github || item.source == .cloned {
            if item.isAvailableLocally {
                Button("Choose Different Folder…") {
                    Task { await store.locateLocalFolder(for: item) }
                }
                Button("Remove Local Link") {
                    Task { await store.unlinkLocalFolder(for: item) }
                }
            } else {
                Button("Locate on This Mac…") {
                    Task { await store.locateLocalFolder(for: item) }
                }
            }

            if item.htmlURL != nil {
                Button("Open on GitHub") {
                    store.openCatalogItemOnGitHub(item)
                }
            }
        }
    }

    @ViewBuilder
    private func availabilityBadge(for item: RepositoryCatalogItem) -> some View {
        if item.isAvailableLocally {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .help("Linked on this Mac")
        } else if item.source == .github || item.source == .cloned {
            Image(systemName: item.source == .cloned ? "arrow.down.circle" : "icloud")
                .symbolRenderingMode(.hierarchical)
                .help("Not linked — use the menu to locate the local folder")
        } else {
            Color.clear
                .frame(width: 18, height: 18)
        }
    }

    private func rowSubtitle(for item: RepositoryCatalogItem) -> String {
        if item.isAvailableLocally, let path = item.localPathSubtitle {
            if let fullName = item.subtitle, item.source == .github || item.source == .cloned {
                return "\(fullName) · \(path)"
            }
            return path
        }
        return item.subtitle ?? "Local folder"
    }

    private func isSelected(_ item: RepositoryCatalogItem) -> Bool {
        guard let localURL = item.localURL, let repoURL = store.repoURL else { return false }
        return RepoAccessManager.normalizedPath(localURL) == RepoAccessManager.normalizedPath(repoURL)
    }
}
