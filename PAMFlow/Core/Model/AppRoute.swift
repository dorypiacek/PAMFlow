//
//  AppRoute.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation

/// Top-level navigation destinations for the single-window PAMFlow app.
///
/// Routes carry only stable identifiers or lightweight value types. Screen
/// models fetch richer state from SwiftData or stores when they render.
enum AppRoute: Hashable {
    case welcome
    case projectSelection
    case dataTypeSelection
    case moduleFlow(moduleID: ModuleID)
    case moduleScreen(ModuleScreenRoute)
}

/// A screen owned by a feature module workflow.
struct ModuleScreenRoute: Hashable {
    let moduleID: ModuleID
    let screenID: String
    let projectID: UUID
    let startAtLastReviewed: Bool

    init(moduleID: ModuleID, screenID: String, projectID: UUID, startAtLastReviewed: Bool = false) {
        self.moduleID = moduleID
        self.screenID = screenID
        self.projectID = projectID
        self.startAtLastReviewed = startAtLastReviewed
    }
}
