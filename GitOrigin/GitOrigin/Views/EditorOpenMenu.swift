//
//  EditorOpenMenu.swift
//  GitOrigin
//
//  Shared Open In menu with detected editors and custom editor configuration.
//

import SwiftUI

struct EditorOpenMenu<Label: View>: View {
    let open: (ExternalEditor) -> Void
    @ViewBuilder let label: () -> Label

    @State private var editors = ExternalEditorDiscovery.availableEditors()

    var body: some View {
        Menu {
            if editors.isEmpty {
                Button("No Editors Found") {}
                    .disabled(true)
            } else {
                ForEach(editors) { editor in
                    Button(editor.name) {
                        open(editor)
                    }
                }
            }

            Divider()

            Button("Choose Custom Editor…") {
                Task { @MainActor in
                    if let editor = ExternalEditorDiscovery.chooseCustomEditor() {
                        editors = ExternalEditorDiscovery.availableEditors()
                        open(editor)
                    } else {
                        editors = ExternalEditorDiscovery.availableEditors()
                    }
                }
            }
        } label: {
            label()
        }
        .onAppear {
            editors = ExternalEditorDiscovery.availableEditors()
        }
    }
}
