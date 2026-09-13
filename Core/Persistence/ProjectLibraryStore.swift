//
//  ProjectLibraryStore.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation

/// Persistence boundary for the user-selected PAMFlow project library folder.
protocol ProjectLibraryStoring {
    func load() -> URL?
    func save(_ url: URL) throws
}

/// Stores the project library folder as a security-scoped bookmark.
///
/// Bookmark storage is required because the app is sandboxed and needs durable
/// access to user-selected folders across launches.
final class ProjectLibraryStore: ProjectLibraryStoring {
    private let key = "project_library_bookmark"

    func load() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func save(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: key)
    }
}
