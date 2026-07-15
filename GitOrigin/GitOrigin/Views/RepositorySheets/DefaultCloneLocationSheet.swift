//
//  DefaultCloneLocationSheet.swift
//  GitOrigin
//

import SwiftUI

struct DefaultCloneLocationSheet: View {
    @Bindable var store: RepositoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RepositorySheetContainer(title: "Choose Clone Location") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick a folder on your Mac. GitOrigin will create a GitOrigin folder inside it and store all clones there by default.")
                    .foregroundStyle(.secondary)

                Button("Choose Folder…") {
                    Task {
                        await store.configureDefaultCloneLocationFromPanel()
                        if CloneLocationSettings.isConfigured {
                            store.presentCloneSheetIfReady()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
    }
}
