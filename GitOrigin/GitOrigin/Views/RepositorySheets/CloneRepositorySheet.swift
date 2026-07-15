//
//  CloneRepositorySheet.swift
//  GitOrigin
//

import SwiftUI

struct CloneRepositorySheet: View {
    @Bindable var store: RepositoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isContentReady = false

    var body: some View {
        RepositorySheetContainer(title: "Clone Repository") {
            Group {
                if isContentReady {
                    formContent
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                store.prepareCloneSheet()
                isContentReady = true
            }
        }
        .task(id: store.cloneSourceMode) {
            guard store.cloneSourceMode == .myRepositories else { return }
            await store.loadCloneCandidatesIfNeeded()
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Source", selection: $store.cloneSourceMode) {
                Text("My Repositories").tag(CloneSourceMode.myRepositories)
                Text("Public URL").tag(CloneSourceMode.publicURL)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 8) {
                Text(store.cloneSourceMode == .myRepositories ? "Repository" : "GitHub URL")
                    .font(.headline)

                if store.cloneSourceMode == .myRepositories {
                    if store.isLoadingCloneCandidates {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading repositories…")
                                .foregroundStyle(.secondary)
                        }
                    } else if store.cloneCandidates.isEmpty {
                        Text("No GitHub repositories found for your account.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Repository", selection: $store.selectedCloneCandidateID) {
                            ForEach(store.cloneCandidates) { repo in
                                Text(repo.fullName).tag(Optional(repo.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    TextField("owner/repo or GitHub URL", text: $store.publicCloneReference)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Clone To")
                    .font(.headline)

                HStack(alignment: .top) {
                    Text(store.cloneDestinationPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") {
                        store.chooseCloneDestination()
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Clone") {
                    Task {
                        await store.cloneSelectedRepository()
                        if store.activeRepositorySheet == nil {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canClone || store.isCloningRepository)
            }
        }
    }
}

enum CloneSourceMode: String, CaseIterable {
    case myRepositories
    case publicURL
}

extension GitHubRemoteRepository: Identifiable {
    var id: String { fullName }
}
