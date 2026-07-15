//
//  AddedRepositoryRegistry.swift
//  GitOrigin
//
//  Persists repositories the user added through GitOrigin (not the full GitHub account list).
//

import Foundation

struct AddedRepositoryRecord: Codable, Equatable, Identifiable {
    let id: String
    let owner: String
    let name: String
    let fullName: String?
    let htmlURL: String?
    let localBookmark: Data
}

@MainActor
final class AddedRepositoryRegistry {
    private static let storageKey = "addedRepositories"

    func catalogItems() -> [RepositoryCatalogItem] {
        loadRecords().compactMap { record in
            guard let url = resolveBookmark(record.localBookmark) else { return nil }
            return RepositoryCatalogItem(
                id: record.id,
                owner: record.owner,
                name: record.name,
                fullName: record.fullName,
                localURL: url.standardizedFileURL,
                htmlURL: record.htmlURL.flatMap(URL.init(string:))
            )
        }
        .sorted { lhs, rhs in
            if lhs.owner != rhs.owner {
                return lhs.owner.localizedStandardCompare(rhs.owner) == .orderedAscending
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func register(
        localURL: URL,
        owner: String,
        name: String,
        fullName: String?,
        htmlURL: URL?
    ) {
        let path = RepoAccessManager.normalizedPath(localURL)
        var records = loadRecords()
        records.removeAll { record in
            guard let url = resolveBookmark(record.localBookmark) else { return false }
            return RepoAccessManager.normalizedPath(url) == path
        }

        guard let bookmark = makeBookmark(for: localURL) else { return }

        let record = AddedRepositoryRecord(
            id: fullName ?? "local-\(path)",
            owner: owner,
            name: name,
            fullName: fullName,
            htmlURL: htmlURL?.absoluteString,
            localBookmark: bookmark
        )
        records.append(record)
        saveRecords(records)
    }

    func remove(id: String) {
        var records = loadRecords()
        records.removeAll { $0.id == id }
        saveRecords(records)
    }

    // MARK: - Private

    private func loadRecords() -> [AddedRepositoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let records = try? JSONDecoder().decode([AddedRepositoryRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func saveRecords(_ records: [AddedRepositoryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
