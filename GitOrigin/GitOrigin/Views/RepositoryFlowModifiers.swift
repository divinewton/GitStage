//
//  RepositoryFlowModifiers.swift
//  GitOrigin
//
//  Shared sheets, alerts, and dialogs for repository management flows.
//

import SwiftUI

struct RepositoryFlowModifiers: ViewModifier {
    @Bindable var store: RepositoryStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $store.activeRepositorySheet) { sheet in
                switch sheet {
                case .addExisting:
                    AddExistingRepositorySheet(store: store)
                case .create:
                    CreateRepositorySheet(store: store)
                case .clone:
                    CloneRepositorySheet(store: store)
                case .setCloneLocation:
                    DefaultCloneLocationSheet(store: store)
                }
            }
            .sheet(isPresented: $store.showCreateBranchSheet) {
                CreateBranchSheet(store: store)
            }
            .alert(item: $store.presentedAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert(
                "Uncommitted Changes",
                isPresented: $store.showDirtyCheckoutConfirmation
            ) {
                Button("Cancel", role: .cancel) {
                    store.cancelCheckout()
                }
                Button("Checkout Anyway", role: .destructive) {
                    Task { await store.confirmCheckout() }
                }
            } message: {
                if let branch = store.pendingCheckoutBranch {
                    Text("You have uncommitted changes. Checking out “\(branch.name)” may fail or carry changes over.")
                }
            }
            .confirmationDialog(
                removeRepositoryTitle,
                isPresented: removeRepositoryDialogIsPresented,
                titleVisibility: .visible
            ) {
                Button("Remove from GitOrigin") {
                    store.confirmRemoveAddedRepository(moveToTrash: false)
                }
                Button("Remove and Move to Trash", role: .destructive) {
                    store.confirmRemoveAddedRepository(moveToTrash: true)
                }
                Button("Cancel", role: .cancel) {
                    store.cancelRemoveAddedRepository()
                }
            } message: {
                Text("The folder will stay on your Mac unless you move it to the Trash.")
            }
    }

    private var removeRepositoryTitle: String {
        if let name = store.pendingRepositoryRemoval?.name {
            "Remove “\(name)” from GitOrigin?"
        } else {
            "Remove Repository from GitOrigin?"
        }
    }

    private var removeRepositoryDialogIsPresented: Binding<Bool> {
        Binding(
            get: { store.pendingRepositoryRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    store.cancelRemoveAddedRepository()
                }
            }
        )
    }
}

extension View {
    func repositoryFlowModifiers(store: RepositoryStore) -> some View {
        modifier(RepositoryFlowModifiers(store: store))
    }
}
