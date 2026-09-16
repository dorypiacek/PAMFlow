//
//  AppRoute.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation
import UI
import Core

/// Top-level navigation destinations for the single-window PAMFlow app.
///
/// Routes carry only stable identifiers or lightweight value types. Screen
/// models fetch richer state from SwiftData or stores when they render.
enum AppRoute: Hashable {
    case welcome
    case projectSelection
    case dataTypeSelection
    case moduleWorkflow
}
