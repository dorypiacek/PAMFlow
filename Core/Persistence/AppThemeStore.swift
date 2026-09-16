//
//  AppThemeStore.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation

/// Persistence boundary for the user's selected appearance mode.
public protocol AppThemeStoring {
    func load() -> AppTheme
    func save(_ theme: AppTheme)
}

/// UserDefaults-backed theme store.
public final class AppThemeStore: AppThemeStoring {
    private let key = "app_theme"

    public init() {}

    public func load() -> AppTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: key) else {
            return .dark
        }

        return AppTheme(rawValue: rawValue) ?? .dark
    }

    public func save(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}
