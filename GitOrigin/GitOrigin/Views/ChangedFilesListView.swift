//
//  ChangedFilesListView.swift
//  GitOrigin
//
//  Selectable list of porcelain status entries for the open repository.
//

import SwiftUI

struct ChangedFilesListView: View {
    @Bindable var store: RepositoryStore

    var body: some View {
        if store.repoURL == nil {
            ContentUnavailableView(
                "No Repository",
                systemImage: "folder",
                description: Text("Choose a repository from the sidebar or open a folder.")
            )
        } else if store.changedFiles.isEmpty {
            ContentUnavailableView(
                "No Changes",
                systemImage: "checkmark.circle",
                description: Text("Working tree is clean on \(store.currentBranch ?? "this branch").")
            )
        } else {
            List(store.changedFiles, selection: selectedFileID) { file in
                HStack(spacing: 8) {
                    Toggle(isOn: stagingBinding(for: file)) {
                        EmptyView()
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    ChangedFileBadge(file: file)
                    Text(file.filepath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .tag(file.id)
                .contextMenu {
                    Button("Discard Changes", role: .destructive) {
                        Task { await store.discardChanges(for: file) }
                    }

                    EditorOpenMenu(open: { editor in
                        store.openChangedFileInEditor(file, editor: editor)
                    }) {
                        Text("Open In")
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                stageAllRow
            }
        }
    }

    private var stageAllRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: stageAllBinding) {
                Text("Stage All")
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.checkbox)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var allStaged: Bool {
        !store.changedFiles.isEmpty
            && store.changedFiles.allSatisfy { $0.stagingState == .staged }
    }

    private var stageAllBinding: Binding<Bool> {
        Binding(
            get: { allStaged },
            set: { shouldStage in
                Task {
                    if shouldStage {
                        await store.stageAll()
                    } else {
                        await store.unstageAll()
                    }
                }
            }
        )
    }

    private func stagingBinding(for file: ChangedFile) -> Binding<Bool> {
        Binding(
            get: { file.stagingState != .unstaged },
            set: { isStaged in
                Task {
                    if isStaged {
                        await store.stage(file: file)
                    } else {
                        await store.unstage(file: file)
                    }
                }
            }
        )
    }

    private var selectedFileID: Binding<String?> {
        Binding(
            get: { store.selectedFile?.id },
            set: { store.selectFile(id: $0) }
        )
    }
}
