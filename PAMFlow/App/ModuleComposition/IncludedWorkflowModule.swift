//
//  IncludedWorkflowModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Feature-module adapter for workflows included in the current app target.
@MainActor
final class IncludedWorkflowModule: FeatureModule {
    let workflowModule: WorkflowModule

    var details: ModuleDetails {
        workflowModule.details
    }

    init(workflowModule: WorkflowModule) {
        self.workflowModule = workflowModule
    }

    func makeCoordinator(context: ModuleContext) -> ModuleCoordinating {
        IncludedWorkflowCoordinator(
            workflowModule: workflowModule,
            appCoordinator: context.appCoordinator,
            projectScanService: context.dependencies.projectScanService
        )
    }
}

@MainActor
private final class IncludedWorkflowCoordinator: ModuleCoordinating {
    let workflowModule: WorkflowModule

    var moduleID: ModuleID {
        ModuleID(rawValue: workflowModule.id)
    }

    private let appCoordinator: AppCoordinating
    private let projectScanService: ProjectScanServicing

    init(
        workflowModule: WorkflowModule,
        appCoordinator: AppCoordinating,
        projectScanService: ProjectScanServicing
    ) {
        self.workflowModule = workflowModule
        self.appCoordinator = appCoordinator
        self.projectScanService = projectScanService
    }

    func openLatestProject(_ project: Project) {
        switch project.workflowStatus {
        case .created, .scanInProgress:
            appCoordinator.scanProject(project)
        case .scanCompleted:
            if workflowModule.requiresSharkTrack {
                appCoordinator.openSharkTrackProcessing(project)
            } else {
                appCoordinator.openNewProjectOverview(project)
            }
        case .manualAuditInProgress:
            appCoordinator.openManualAudit(project, startAtLastReviewed: false)
        case .manualAuditCompleted:
            appCoordinator.openManualAuditOverview(project)
        case .pamguardSetupReady:
            if workflowModule.usesPAMGuard {
                appCoordinator.openPAMGuardSetup(project)
            } else {
                appCoordinator.openManualAuditOverview(project)
            }
        case .processingProjectCreated:
            if workflowModule.requiresSharkTrack {
                if hasReviewItems(project) {
                    appCoordinator.openManualAudit(project, startAtLastReviewed: false)
                } else {
                    appCoordinator.openManualAuditOverview(project)
                }
            } else {
                appCoordinator.openPAMGuardWaiting(project)
            }
        case .processingRunImported:
            if workflowModule.usesPAMGuard {
                appCoordinator.openManualAuditOverview(project)
            } else {
                appCoordinator.openNewProjectOverview(project)
            }
        case .runOverviewCompleted:
            if workflowModule.usesPAMGuard {
                appCoordinator.openManualAudit(project, startAtLastReviewed: false)
            } else {
                appCoordinator.openNewProjectOverview(project)
            }
        case .detectionReviewInProgress:
            if workflowModule.usesPAMGuard {
                appCoordinator.openManualAudit(project, startAtLastReviewed: true)
            } else {
                appCoordinator.openNewProjectOverview(project)
            }
        case .completed:
            appCoordinator.openProjectCompletion(project)
        }
    }

    func openReadOnlyProject(_ project: Project) {
        appCoordinator.openNewProjectOverview(project)
    }

    private func hasReviewItems(_ project: Project) -> Bool {
        (try? projectScanService.loadSummary(for: project).fileCount) ?? 0 > 0
    }
}

extension WorkflowModule {
    var moduleID: ModuleID {
        ModuleID(rawValue: id)
    }

    var details: ModuleDetails {
        ModuleDetails(
            id: moduleID,
            title: selectionTitle,
            subtitle: selectionSubtitle,
            iconName: selectionIconName,
            projectNamePrefix: projectNamePrefix,
            libraryFolderName: libraryFolderName,
            supportedFileExtensions: supportedFileExtensions
        )
    }
}
