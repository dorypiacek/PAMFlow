//
//  BRUVWorkflowModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import SwiftUI

/// Feature module for baited remote underwater video projects and related RUV workflows.
@MainActor
final class BRUVWorkflowModule: FeatureModule {
    let details: ModuleDetails

    private let projectType: BRUVProjectType

    init(projectType: BRUVProjectType) {
        self.projectType = projectType
        details = BRUVModuleConfiguration.details(for: projectType)
    }

    func makeCoordinator(context: ModuleContext) -> ModuleCoordinating {
        WorkflowCoordinator(
            projectType: projectType,
            details: details,
            workflowActions: context.workflowActions,
            dependencies: BRUVWorkflowDependencies(sharedDependencies: context.dependencies)
        )
    }
}

/// Service dependencies required by the BRUV workflow module.
private struct BRUVWorkflowDependencies {
    let projectFileService: ProjectFileServicing
    let projectScanService: ProjectScanServicing
    let sharkTrackService: SharkTrackServicing
    let fileSelectionService: FileSelecting

    init(
        projectFileService: ProjectFileServicing,
        projectScanService: ProjectScanServicing,
        sharkTrackService: SharkTrackServicing,
        fileSelectionService: FileSelecting
    ) {
        self.projectFileService = projectFileService
        self.projectScanService = projectScanService
        self.sharkTrackService = sharkTrackService
        self.fileSelectionService = fileSelectionService
    }

    init(sharedDependencies: SharedAppDependencies) {
        self.init(
            projectFileService: sharedDependencies.projectFileService,
            projectScanService: sharedDependencies.projectScanService,
            sharkTrackService: SharkTrackService(),
            fileSelectionService: sharedDependencies.fileSelectionService
        )
    }
}

private enum WorkflowScreenID {
    static let scanProject = "scan_project"
    static let projectOverview = "project_overview"
    static let sharkTrackProcessing = "sharktrack_processing"
    static let manualAudit = "manual_audit"
    static let manualAuditOverview = "manual_audit_overview"
    static let projectCompletion = "project_completion"
}

private enum WorkflowScreen {
    case scanProject
    case projectOverview
    case sharkTrackProcessing
    case manualAudit
    case manualAuditOverview
    case projectCompletion

    var id: String {
        switch self {
        case .scanProject:
            WorkflowScreenID.scanProject
        case .projectOverview:
            WorkflowScreenID.projectOverview
        case .sharkTrackProcessing:
            WorkflowScreenID.sharkTrackProcessing
        case .manualAudit:
            WorkflowScreenID.manualAudit
        case .manualAuditOverview:
            WorkflowScreenID.manualAuditOverview
        case .projectCompletion:
            WorkflowScreenID.projectCompletion
        }
    }
}

@MainActor
private final class WorkflowCoordinator: ModuleCoordinating {
    var moduleID: ModuleID {
        details.id
    }
    private(set) var currentScreen: AnyView = AnyView(EmptyView())

    private let projectType: BRUVProjectType
    private let details: ModuleDetails
    private let workflowActions: WorkflowActionHandling
    private let dependencies: BRUVWorkflowDependencies
    private var currentRoute: ModuleScreenRoute?

    init(
        projectType: BRUVProjectType,
        details: ModuleDetails,
        workflowActions: WorkflowActionHandling,
        dependencies: BRUVWorkflowDependencies
    ) {
        self.projectType = projectType
        self.details = details
        self.workflowActions = workflowActions
        self.dependencies = dependencies
    }

    func startProject() {
        currentRoute = nil
        currentScreen = AnyView(
            ProjectSetupView(
                viewModel: BaseProjectSetupViewModel(
                    configuration: BRUVModuleConfiguration.makeSetupConfiguration(for: projectType),
                    projectFileService: dependencies.projectFileService,
                    fileSelectionService: dependencies.fileSelectionService
                )
            )
        )
    }

    private func makeScreen(for route: ModuleScreenRoute) -> AnyView {
        switch route.screenID {
        case WorkflowScreenID.scanProject:
            AnyView(
                ScanProjectView(
                    projectID: route.projectID,
                    supportedFileExtensions: details.supportedFileExtensions,
                    scanAnalyzer: BRUVScanAnalyzer(projectType: projectType)
                )
            )
        case WorkflowScreenID.projectOverview:
            AnyView(
                NewProjectOverviewView(
                    projectID: route.projectID,
                    viewModel: BRUVProjectOverviewViewModel(
                        projectScanService: dependencies.projectScanService,
                        projectType: projectType
                    )
                )
            )
        case WorkflowScreenID.sharkTrackProcessing:
            AnyView(
                SharkTrackProcessingView(
                    projectID: route.projectID,
                    workflowActions: workflowActions,
                    sharkTrackService: dependencies.sharkTrackService,
                    projectScanService: dependencies.projectScanService
                )
            )
        case WorkflowScreenID.manualAudit:
            AnyView(
                ManualAuditView(
                    projectID: route.projectID,
                    startAtLastReviewed: route.startAtLastReviewed,
                    viewModel: BRUVManualAuditViewModel(
                        projectScanService: dependencies.projectScanService
                    )
                )
            )
        case WorkflowScreenID.manualAuditOverview:
            AnyView(
                ManualAuditOverviewView(
                    projectID: route.projectID,
                    viewModel: BRUVManualAuditOverviewViewModel(
                        projectID: route.projectID,
                        projectScanService: dependencies.projectScanService
                    )
                )
            )
        case WorkflowScreenID.projectCompletion:
            AnyView(ProjectCompletionView(projectID: route.projectID, projectScanService: dependencies.projectScanService))
        default:
            AnyView(ProjectSelectionView())
        }
    }

    func goBack() {
        guard let currentRoute else {
            workflowActions.exitWorkflow()
            return
        }

        switch currentRoute.screenID {
        case WorkflowScreenID.scanProject:
            workflowActions.exitWorkflow()
        case WorkflowScreenID.projectOverview:
            show(.scanProject, projectID: currentRoute.projectID)
        case WorkflowScreenID.sharkTrackProcessing:
            show(.projectOverview, projectID: currentRoute.projectID)
        case WorkflowScreenID.manualAudit:
            show(.projectOverview, projectID: currentRoute.projectID)
        case WorkflowScreenID.manualAuditOverview:
            show(.manualAudit, projectID: currentRoute.projectID, startAtLastReviewed: true)
        case WorkflowScreenID.projectCompletion:
            show(.manualAuditOverview, projectID: currentRoute.projectID)
        default:
            workflowActions.exitWorkflow()
        }
    }

    func goToNextStep(for project: Project, startAtLastReviewed: Bool = false) {
        guard let currentRoute else {
            resume(project: project, startAtLastReviewed: startAtLastReviewed)
            return
        }

        switch currentRoute.screenID {
        case WorkflowScreenID.projectOverview:
            showNextFromProjectOverview(project)
        default:
            resume(project: project, startAtLastReviewed: startAtLastReviewed)
        }
    }

    func resume(project: Project, startAtLastReviewed: Bool = false) {
        switch project.workflowStatus {
        case .created, .scanInProgress:
            show(.scanProject, for: project)
        case .scanCompleted:
            show(.sharkTrackProcessing, for: project)
        case .manualAuditInProgress, .detectionReviewInProgress:
            show(.manualAudit, for: project, startAtLastReviewed: startAtLastReviewed)
        case .manualAuditCompleted:
            show(.manualAuditOverview, for: project)
        case .completed:
            show(.projectCompletion, for: project)
        default:
            show(.manualAuditOverview, for: project)
        }
    }

    func openReadOnlyProject(_ project: Project) {
        show(.projectCompletion, for: project)
    }

    private func showNextFromProjectOverview(_ project: Project) {
        guard project.workflowStatus == .scanCompleted else {
            resume(project: project)
            return
        }

        show(.sharkTrackProcessing, for: project)
    }

    private func show(_ screen: WorkflowScreen, for project: Project, startAtLastReviewed: Bool = false) {
        project.lastOpenedAt = .now
        show(screen, projectID: project.id, startAtLastReviewed: startAtLastReviewed)
    }

    private func show(_ screen: WorkflowScreen, projectID: UUID, startAtLastReviewed: Bool = false) {
        let route = ModuleScreenRoute(
            moduleID: moduleID,
            screenID: screen.id,
            projectID: projectID,
            startAtLastReviewed: startAtLastReviewed
        )
        currentRoute = route
        currentScreen = makeScreen(for: route)
    }
}
