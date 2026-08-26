//
//  ProjectWorkflowStatus.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation

/// Durable workflow milestone for a project.
enum ProjectWorkflowStatus: String, CaseIterable, Codable, Hashable {
    case created
    case scanInProgress
    case scanCompleted
    case manualAuditInProgress
    case manualAuditCompleted
    case pamguardSetupReady
    case processingProjectCreated
    case processingRunImported
    case runOverviewCompleted
    case detectionReviewInProgress
    case completed

    var title: String {
        switch self {
        case .created:
            Strings.WorkflowStatus.created
        case .scanInProgress:
            Strings.WorkflowStatus.scanInProgress
        case .scanCompleted:
            Strings.WorkflowStatus.scanCompleted
        case .manualAuditInProgress:
            Strings.WorkflowStatus.manualAuditInProgress
        case .manualAuditCompleted:
            Strings.WorkflowStatus.manualAuditCompleted
        case .pamguardSetupReady:
            Strings.WorkflowStatus.pamguardSetupReady
        case .processingProjectCreated:
            Strings.WorkflowStatus.processingProjectCreated
        case .processingRunImported:
            Strings.WorkflowStatus.processingRunImported
        case .runOverviewCompleted:
            Strings.WorkflowStatus.runOverviewCompleted
        case .detectionReviewInProgress:
            Strings.WorkflowStatus.detectionReviewInProgress
        case .completed:
            Strings.WorkflowStatus.completed
        }
    }

    var lastCompletedStepTitle: String {
        switch self {
        case .created, .scanInProgress:
            Strings.WorkflowStatus.projectCreated
        case .scanCompleted, .manualAuditInProgress:
            Strings.WorkflowStatus.scanCompleted
        case .manualAuditCompleted:
            Strings.WorkflowStatus.manualAuditCompleted
        case .pamguardSetupReady, .processingProjectCreated:
            Strings.WorkflowStatus.pamguardSetupReady
        case .processingRunImported, .runOverviewCompleted:
            Strings.WorkflowStatus.processingRunImported
        case .detectionReviewInProgress:
            Strings.WorkflowStatus.runOverviewCompleted
        case .completed:
            Strings.WorkflowStatus.allDetectionsReviewed
        }
    }

    var continueActionTitle: String {
        switch self {
        case .created, .scanInProgress:
            Strings.WorkflowStatus.resumeScan
        case .scanCompleted:
            Strings.WorkflowStatus.continueToOverview
        case .manualAuditInProgress:
            Strings.WorkflowStatus.continueManualAudit
        case .manualAuditCompleted:
            Strings.WorkflowStatus.openAuditOverview
        case .pamguardSetupReady:
            Strings.WorkflowStatus.openPamguardSetup
        case .processingProjectCreated:
            Strings.WorkflowStatus.importProcessingRun
        case .processingRunImported:
            Strings.WorkflowStatus.openRunOverview
        case .runOverviewCompleted, .detectionReviewInProgress:
            Strings.WorkflowStatus.continueDetectionReview
        case .completed:
            Strings.WorkflowStatus.viewProject
        }
    }
}
