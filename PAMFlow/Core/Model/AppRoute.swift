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
    case projectSetup(module: WorkflowModule)
    case scanProject(projectID: UUID)
    case newProjectOverview(projectID: UUID)
    case sharkTrackProcessing(projectID: UUID)
    case manualAudit(projectID: UUID, startAtLastReviewed: Bool = false)
    case manualAuditOverview(projectID: UUID)
    case pamguardSetup(projectID: UUID)
    case pamguardWaiting(projectID: UUID)
    case pamguardProcessing(projectID: UUID)
    case projectCompletion(projectID: UUID)
}
