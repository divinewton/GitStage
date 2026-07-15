//
//  RepositorySidebarView.swift
//  GitStage
//
//  Searchable sidebar of repositories added through GitStage, grouped by owner.
//

import AppKit
import SwiftUI

struct RepositorySidebarView: View {
    @Bindable var store: RepositoryStore

    @State private var searchText = ""
    @State private var isRecentExpanded = true
    @State private var expandedOwners: Set<String> = []
    @State private var hoveredRepositoryID: String?

    var body: some View {
        VStack(spacing: 0) {
            sidebarControls
            Divider()
            repositoryList
        }
        .navigationTitle("Repositories")
        .onAppear {
            expandedOwners = Set(ownerSections.map(\.id))
            store.refreshRepositoryCatalog()
        }
        .onChange(of: store.catalogItems.count) { _, _ in
            expandedOwners.formUnion(Set(ownerSections.map(\.id)))
        }
    }

    private var sidebarControls: some View {
        HStack(spacing: 8) {
            TextField("Search repositories", text: $searchText)
                .textFieldStyle(.roundedBorder)

            RepositoryAddMenu(store: store) {
                Text("Add")
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var repositoryList: some View {
        List {
            if filteredRecentItems.isEmpty && filteredOwnerSections.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No repositories match your search.")
                )
            }

            if !filteredRecentItems.isEmpty {
                Section(isExpanded: $isRecentExpanded) {
                    ForEach(filteredRecentItems) { item in
                        repositoryRow(item)
                    }
                } header: {
                    Text("Recent")
                }
            }

            ForEach(filteredOwnerSections) { section in
                Section(isExpanded: ownerExpansionBinding(for: section.id)) {
                    ForEach(section.items) { item in
                        repositoryRow(item)
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Sections

    private var filteredRecentItems: [RepositoryCatalogItem] {
        filter(recentItems)
    }

    private var filteredOwnerSections: [OwnerSection] {
        ownerSections.compactMap { section in
            let items = filter(section.items)
            guard !items.isEmpty else { return nil }
            return OwnerSection(id: section.id, title: section.title, items: items)
        }
    }

    private var recentItems: [RepositoryCatalogItem] {
        let order = store.recentRepositoryPathOrder
        var seen = Set<String>()

        return order.prefix(3).compactMap { path in
            guard let item = store.catalogItems.first(where: {
                RepoAccessManager.normalizedPath($0.localURL) == path
            }) else {
                return nil
            }
            guard seen.insert(item.id).inserted else { return nil }
            return item
        }
    }

    private var ownerSections: [OwnerSection] {
        let grouped = Dictionary(grouping: store.catalogItems) { $0.owner }

        return grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { owner in
            OwnerSection(
                id: owner,
                title: owner,
                items: grouped[owner]?.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
            )
        }
    }

    private func filter(_ items: [RepositoryCatalogItem]) -> [RepositoryCatalogItem] {
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { item in
            item.name.lowercased().contains(query)
                || item.owner.lowercased().contains(query)
                || (item.fullName?.lowercased().contains(query) ?? false)
        }
    }

    private func ownerExpansionBinding(for owner: String) -> Binding<Bool> {
        Binding(
            get: { expandedOwners.contains(owner) },
            set: { isExpanded in
                if isExpanded {
                    expandedOwners.insert(owner)
                } else {
                    expandedOwners.remove(owner)
                }
            }
        )
    }

    // MARK: - Rows

    @ViewBuilder
    private func repositoryRow(_ item: RepositoryCatalogItem) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.openCatalogItem(item) }
            } label: {
                Text(item.name)
                    .fontWeight(isSelected(item) ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                repositoryItemActions(for: item)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .opacity(showRepositoryMenu(for: item) ? 1 : 0)
            .allowsHitTesting(showRepositoryMenu(for: item))
        }
        .listRowBackground(isSelected(item) ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu {
            repositoryItemActions(for: item)
        }
        .onHover { isHovering in
            hoveredRepositoryID = isHovering ? item.id : nil
        }
    }

    private func showRepositoryMenu(for item: RepositoryCatalogItem) -> Bool {
        hoveredRepositoryID == item.id || isSelected(item)
    }

    private func isSelected(_ item: RepositoryCatalogItem) -> Bool {
        guard let repoURL = store.repoURL else { return false }
        return RepoAccessManager.normalizedPath(item.localURL) == RepoAccessManager.normalizedPath(repoURL)
    }

    @ViewBuilder
    private func repositoryItemActions(for item: RepositoryCatalogItem) -> some View {
        Button("Reveal in Finder") {
            store.revealCatalogItemInFinder(item)
        }
        if item.htmlURL != nil {
            Button("Open on GitHub") {
                store.openCatalogItemOnGitHub(item)
            }
        }
        EditorOpenMenu(open: { editor in
            store.openCatalogItemInEditor(item, editor: editor)
        }) {
            Text("Open In")
        }
        Divider()
        Button("Remove from GitStage", role: .destructive) {
            store.requestRemoveAddedRepository(item)
        }
    }
}

private struct OwnerSection: Identifiable {
    let id: String
    let title: String
    let items: [RepositoryCatalogItem]
}
