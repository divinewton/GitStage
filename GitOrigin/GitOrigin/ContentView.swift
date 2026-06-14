//
//  ContentView.swift
//  GitOrigin
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: RepositoryStore

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var sidebar: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("GitOrigin")
                        .font(.headline)
                    Spacer()
                    if store.isLoadingStatus {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let branch = store.currentBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let repoURL = store.repoURL {
                    Text(repoURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let error = store.lastError {
                    Text(error.errorDescription ?? "An unknown error occurred.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .glassEffect(.regular.tint(.red.opacity(0.15)), in: RoundedRectangle(cornerRadius: 8))
                }

                if store.changedFiles.isEmpty {
                    ContentUnavailableView(
                        store.repoURL == nil ? "No Repository" : "No Changes",
                        systemImage: "folder",
                        description: Text(store.repoURL == nil ? "Open a folder to inspect its Git status." : "Working tree is clean.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(store.changedFiles) { file in
                        HStack {
                            statusBadge(for: file)
                            Text(file.filepath)
                                .lineLimit(1)
                        }
                    }
                    .listStyle(.plain)
                }

                HStack(spacing: 8) {
                    Button("Open Repository") {
                        Task { await store.openRepositoryViaPanel() }
                    }
                    .buttonStyle(.glass)

                    Button("Refresh") {
                        Task { await store.refreshStatus() }
                    }
                    .buttonStyle(.glass)
                    .disabled(store.repoURL == nil)
                }
            }
            .padding()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding()
    }

    private var detail: some View {
        ContentUnavailableView(
            "Phase 1 — Git Engine",
            systemImage: "terminal",
            description: Text("Repository status loads here. Diff view arrives in Phase 3.")
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func statusBadge(for file: ChangedFile) -> some View {
        Text(badgeLetter(for: file))
            .font(.caption.bold())
            .frame(width: 20, height: 20)
            .glassEffect(badgeGlass(for: file), in: Circle())
    }

    private func badgeLetter(for file: ChangedFile) -> String {
        switch file.status {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .untracked: "?"
        case .renamed: "R"
        }
    }

    private func badgeGlass(for file: ChangedFile) -> Glass {
        switch file.status {
        case .modified: .regular.tint(.orange.opacity(0.35))
        case .added: .regular.tint(.green.opacity(0.35))
        case .deleted: .regular.tint(.red.opacity(0.35))
        case .untracked: .regular.tint(.blue.opacity(0.35))
        case .renamed: .regular.tint(.purple.opacity(0.35))
        }
    }
}

#Preview {
    ContentView(store: RepositoryStore())
}
