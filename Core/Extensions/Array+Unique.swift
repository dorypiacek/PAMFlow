//
//  Array+Uniquing.swift
//  PAMFlow
//
//  Created by Dory on 12/08/2026.
//

import Foundation

public extension Array where Element: Hashable {
    func uniquedForDisplay() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
            .sorted { String(describing: $0) < String(describing: $1) }
    }
}

public extension Array where Element == String {
    func uniqueStrings() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value).inserted
        }
    }
}

public extension Array where Element == URL {
    func uniqueStandardizedURLs() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}
