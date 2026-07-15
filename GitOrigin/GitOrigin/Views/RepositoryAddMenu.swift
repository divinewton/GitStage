//
//  RepositoryAddMenu.swift
//  GitOrigin
//
//  Shared Add menu for clone, create, and add-existing repository flows.
//

import SwiftUI

struct RepositoryAddMenu<Label: View>: View {
    @Bindable var store: RepositoryStore
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            Button("Clone Repository…") {
                store.presentCloneSheetIfReady()
            }
            Button("Create Repository…") {
                store.presentCreateSheet()
            }
            Button("Add Existing Repository…") {
                store.presentAddExistingSheet()
            }
        } label: {
            label()
        }
        .onHover { isHovering in
            guard isHovering else { return }
            Task { await store.preloadRepositorySheetData() }
        }
    }
}
