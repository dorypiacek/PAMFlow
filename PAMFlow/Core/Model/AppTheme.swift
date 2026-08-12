//
//  AppTheme.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftUI

/// Appearance preference selected by the user.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var title: String {
        switch self {
        case .system:
            Strings.AppTheme.system
        case .light:
            Strings.AppTheme.light
        case .dark:
            Strings.AppTheme.dark
        }
    }
}
