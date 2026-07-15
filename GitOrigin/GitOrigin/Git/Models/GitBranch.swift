//
//  GitBranch.swift
//  GitOrigin
//
//  Local or remote branch with current-branch and upstream metadata.
//

import Foundation

struct GitBranch: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let isCurrent: Bool
    let trackingNote: String?
    let isRemote: Bool

    init(name: String, isCurrent: Bool, trackingNote: String?, isRemote: Bool = false) {
        self.name = name
        self.isCurrent = isCurrent
        self.trackingNote = trackingNote
        self.isRemote = isRemote
    }

    /// Local branch name suitable for `git checkout --track`.
    var localCheckoutName: String? {
        guard isRemote else { return name }
        guard let slash = name.firstIndex(of: "/") else { return nil }
        let localName = String(name[name.index(after: slash)...])
        guard !localName.isEmpty, localName != "HEAD" else { return nil }
        return localName
    }

    var checkoutDisplayName: String {
        localCheckoutName ?? name
    }
}

extension Array where Element == GitBranch {
    /// Remote branches that do not already exist as a local branch with the same name.
    func remoteOnlyBranches() -> [GitBranch] {
        let localNames = Set(filter { !$0.isRemote }.map(\.name))
        return filter { branch in
            guard branch.isRemote, let localName = branch.localCheckoutName else { return false }
            return !localNames.contains(localName)
        }
    }
}
