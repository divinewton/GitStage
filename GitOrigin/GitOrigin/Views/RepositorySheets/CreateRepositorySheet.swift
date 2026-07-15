//
//  CreateRepositorySheet.swift
//  GitOrigin
//

import SwiftUI

struct CreateRepositorySheet: View {
    @Bindable var store: RepositoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var isContentReady = false

    var body: some View {
        RepositorySheetContainer(title: "Create Repository") {
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
                store.prepareCreateRepositorySheet()
                isContentReady = true
            }
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Repository name", text: $store.newRepoName)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $store.newRepoDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            Toggle("Private repository", isOn: $store.newRepoIsPrivate)

            VStack(alignment: .leading, spacing: 8) {
                Text("Local Location")
                    .font(.headline)

                HStack(alignment: .top) {
                    Text(store.newRepoDestinationPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") {
                        store.chooseCreateRepositoryDestination()
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Create on GitHub") {
                    Task {
                        await store.createRepositoryOnGitHub()
                        if store.activeRepositorySheet == nil {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.newRepoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isCreatingRepository)
            }
        }
    }
}
