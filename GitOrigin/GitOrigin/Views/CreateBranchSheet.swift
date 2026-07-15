//
//  CreateBranchSheet.swift
//  GitOrigin
//
//  Modal sheet for naming a new branch and optional start point.
//

import SwiftUI

struct CreateBranchSheet: View {
    @Bindable var store: RepositoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Branch")
                .font(.title2.weight(.semibold))

            TextField("Branch name", text: $store.newBranchName)
                .textFieldStyle(.roundedBorder)

            TextField("Start from", text: $store.newBranchBase)
                .textFieldStyle(.roundedBorder)

            Text("Creates and checks out a new branch from the selected starting point.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task {
                        await store.createBranch()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(store.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
