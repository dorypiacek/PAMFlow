//
//  AppThemeStore.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation

/// Persistence boundary for the user's selected appearance mode.
protocol AppThemeStoring {
    func load() -> AppTheme
    func save(_ theme: AppTheme)
}

/// UserDefaults-backed theme store.
final class AppThemeStore: AppThemeStoring {
    private let key = "app_theme"

    func load() -> AppTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: key) else {
            return .dark
        }

        return AppTheme(rawValue: rawValue) ?? .dark
    }

    func save(_ theme: AppTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: key)
    }
}
