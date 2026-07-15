//
//  CommitBoxView.swift
//  GitOrigin
//
//  Summary, description, co-authors, and commit action at the bottom of detail.
//

import SwiftUI

struct CommitBoxView: View {
    @Bindable var store: RepositoryStore
    @FocusState private var focusedField: CommitField?

    private enum CommitField: Hashable {
        case summary
        case description
        case coAuthors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Commit")
                    .font(.headline)
                Spacer()
                if store.stagedFileCount > 0 {
                    Text("\(store.stagedFileCount) staged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Summary (required)", text: $store.commitSummary)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .summary)
                .onSubmit {
                    Task { await store.commit() }
                }

            TextField("Description (optional)", text: $store.commitDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .focused($focusedField, equals: .description)

            TextField("Co-authors (optional)", text: $store.commitCoAuthors, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($focusedField, equals: .coAuthors)

            Text("One co-author per line: Name (email@example.com)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(commitButtonTitle) {
                Task { await store.commit() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCommit)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35))
        .onChange(of: focusedField) { _, newValue in
            store.isCommitFieldFocused = newValue != nil
        }
        .onAppear {
            store.isCommitFieldFocused = focusedField != nil
        }
    }

    private var commitButtonTitle: String {
        if let branch = store.currentBranch {
            "Commit to \(branch)"
        } else {
            "Commit"
        }
    }

    private var canCommit: Bool {
        !store.commitSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.repoURL != nil
            && !store.isCommitting
    }
}

#Preview {
    CommitBoxView(store: .previewWithChanges)
        .frame(width: 420)
}
