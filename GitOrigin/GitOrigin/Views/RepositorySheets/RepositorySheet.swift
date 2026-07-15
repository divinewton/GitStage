//
//  RepositorySheet.swift
//  GitOrigin
//
//  Sheet types and shared chrome for add / clone / create repository flows.
//

import SwiftUI

enum RepositorySheet: Identifiable {
    case addExisting
    case create
    case clone
    case setCloneLocation

    var id: String {
        switch self {
        case .addExisting: "addExisting"
        case .create: "create"
        case .clone: "clone"
        case .setCloneLocation: "setCloneLocation"
        }
    }

    var title: String {
        switch self {
        case .addExisting: "Add Existing Repository"
        case .create: "Create Repository"
        case .clone: "Clone Repository"
        case .setCloneLocation: "Choose Clone Location"
        }
    }
}

struct RepositorySheetContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            content()
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 520, minHeight: 320)
        .presentationSizing(.fitted)
        .presentationBackground(.regularMaterial)
    }
}
