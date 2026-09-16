//
//  AppTheme.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftUI

/// Appearance preference selected by the user.
public enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    public var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }
}
