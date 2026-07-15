//
//  AddExistingRepositorySheet.swift
//  GitOrigin
//

import SwiftUI

struct AddExistingRepositorySheet: View {
    @Bindable var store: RepositoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RepositorySheetContainer(title: "Add Existing Repository") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose a local folder that already contains a Git repository.")
                    .foregroundStyle(.secondary)

                Button("Choose Folder…") {
                    Task {
                        await store.addExistingRepositoryFromPanel()
                        if store.activeRepositorySheet == nil {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
    }
}
