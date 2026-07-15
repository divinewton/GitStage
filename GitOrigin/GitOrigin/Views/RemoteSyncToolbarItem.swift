//
//  RemoteSyncToolbarItem.swift
//  GitOrigin
//
//  Toolbar control that offers Fetch, Pull, or Push based on upstream state.
//

import SwiftUI

enum RemoteSyncAction: Equatable {
    case fetch
    case pull
    case push

    var title: String {
        switch self {
        case .fetch: "Fetch"
        case .pull: "Pull"
        case .push: "Push"
        }
    }

    var systemImage: String {
        switch self {
        case .fetch: "arrow.clockwise"
        case .pull: "arrow.down.circle"
        case .push: "arrow.up.circle"
        }
    }
}

struct RemoteSyncToolbarItem: View {
    @Bindable var store: RepositoryStore

    private let toolbarWidth: CGFloat = 184
    private let toolbarHeight: CGFloat = 36

    var body: some View {
        Button {
            guard !store.isSyncing else { return }
            Task { await store.performPreferredRemoteSync() }
        } label: {
            Group {
                if store.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: action.systemImage)
                        VStack(alignment: .center, spacing: 1) {
                            Text(action.title)
                            Text(store.lastFetchedDisplay)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
            }
            .frame(width: toolbarWidth, height: toolbarHeight, alignment: .center)
        }
        .buttonStyle(.plain)
        .disabled(store.repoURL == nil || store.isSyncing)
        .help("Sync with the remote repository")
    }

    private var action: RemoteSyncAction {
        store.preferredRemoteSyncAction
    }
}
