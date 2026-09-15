//
//  BRUVWorkflowModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import UI
import Core
import SwiftData
import SwiftUI

/// Feature module for baited remote underwater video projects and related RUV workflows.
@MainActor
public final class BRUVWorkflowModule: FeatureModule {
    public let details: ModuleDetails

    private let projectType: BRUVProjectType

    public init(projectType: BRUVProjectType) {
        self.projectType = projectType
        details = BRUVModuleConfiguration.details(for: projectType)
    }

    public func makeCoordinator(context: ModuleContext) -> ModuleCoordinating {
        WorkflowCoordinator(
            projectType: projectType,
            details: details,
            workflowActions: context.workflowActions,
            dependencies: BRUVWorkflowDependencies(sharedDependencies: context.dependencies)
        )
    }

    public func projectSelectionProgress(
        for project: Project,
        modelContext: ModelContext,
        projectScanService: ProjectScanServicing
    ) -> ProjectSelectionProgress {
        guard var summary = try? projectScanService.loadSummary(for: project) else {
            return ProjectSelectionProgress(reviewed: 0, total: 0, displayPosition: 0)
        }
        sortReviewFiles(&summary.files)
        return ProjectSelectionProgress(project: project, modelContext: modelContext, files: summary.files)
    }

    private func sortReviewFiles(_ files: inout [ProjectScanFile]) {
        files.sort(by: { left, right in
            let leftVideo = left.sourceVideo ?? ""
            let rightVideo = right.sourceVideo ?? ""
            if leftVideo != rightVideo { return leftVideo < rightVideo }

            let leftTrack = left.trackID ?? Int.max
            let rightTrack = right.trackID ?? Int.max
            if leftTrack != rightTrack { return leftTrack < rightTrack }

            return left.relativePath < right.relativePath
        })
    }

    public func projectSelectionPresentation(
        for project: Project,
        folderExists: Bool,
        auditProgressText: String
    ) -> ProjectSelectionPresentation {
        switch project.workflowStatus {
        case .created:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.created,
                primaryActionTitle: Strings.WorkflowStatus.resumeScan,
                lastCompletedStepTitle: Strings.WorkflowStatus.projectCreated
            )
        case .scanInProgress:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.scanInProgress,
                primaryActionTitle: Strings.WorkflowStatus.resumeScan,
                lastCompletedStepTitle: Strings.WorkflowStatus.scanInProgress
            )
        case .scanCompleted:
            ProjectSelectionPresentation(
                statusTitle: Strings.ProjectSelection.processingCompleted,
                primaryActionTitle: Strings.WorkflowStatus.continueToOverview,
                lastCompletedStepTitle: Strings.WorkflowStatus.scanCompleted
            )
        case .manualAuditInProgress, .detectionReviewInProgress, .inProgress:
            ProjectSelectionPresentation(
                statusTitle: BRUVStrings.ProjectSelection.detectionReviewInProgress,
                primaryActionTitle: BRUVStrings.ProjectSelection.continueDetectionReview,
                lastCompletedStepTitle: "\(BRUVStrings.ProjectSelection.detectionReviewProgressPrefix) \(auditProgressText)"
            )
        case .manualAuditCompleted:
            ProjectSelectionPresentation(
                statusTitle: BRUVStrings.ProjectSelection.detectionReviewCompleted,
                primaryActionTitle: BRUVStrings.ProjectSelection.openDetectionOverview,
                lastCompletedStepTitle: BRUVStrings.ProjectSelection.detectionReviewCompleted
            )
        case .completed:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.completed,
                primaryActionTitle: Strings.WorkflowStatus.viewProject,
                lastCompletedStepTitle: Strings.WorkflowStatus.completed
            )
        default:
            ProjectSelectionPresentation(
                statusTitle: project.workflowStatus.genericDisplayTitle,
                primaryActionTitle: Strings.WorkflowStatus.viewProject,
                lastCompletedStepTitle: project.workflowStatus.genericDisplayTitle
            )
        }
    }
}

/// Service dependencies required by the BRUV workflow module.
@MainActor
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
            return AnyView(
                ScanProjectView(
                    projectID: route.projectID,
                    supportedFileExtensions: details.supportedFileExtensions,
                    scanAnalyzer: BRUVScanAnalyzer(projectType: projectType)
                )
            )
        case WorkflowScreenID.projectOverview:
            return AnyView(
                NewProjectOverviewView(
                    projectID: route.projectID,
                    viewModel: BRUVProjectOverviewViewModel(
                        projectScanService: dependencies.projectScanService,
                        projectType: projectType
                    )
                )
            )
        case WorkflowScreenID.sharkTrackProcessing:
            return AnyView(
                SharkTrackProcessingView(
                    projectID: route.projectID,
                    workflowActions: workflowActions,
                    sharkTrackService: dependencies.sharkTrackService,
                    projectScanService: dependencies.projectScanService
                )
            )
        case WorkflowScreenID.manualAudit:
            let viewModel = BRUVManualAuditViewModel(
                projectScanService: dependencies.projectScanService
            )
            return AnyView(
                ManualAuditView(
                    projectID: route.projectID,
                    startAtLastReviewed: route.startAtLastReviewed,
                    viewModel: viewModel
                ) { _, project, file in
                    BRUVManualAuditPreview(viewModel: viewModel, project: project, file: file)
                }
            )
        case WorkflowScreenID.manualAuditOverview:
            return AnyView(
                ManualAuditOverviewView(
                    projectID: route.projectID,
                    viewModel: BRUVManualAuditOverviewViewModel(
                        projectID: route.projectID,
                        projectScanService: dependencies.projectScanService
                    )
                )
            )
        case WorkflowScreenID.projectCompletion:
            return AnyView(BRUVProjectCompletionView(projectID: route.projectID, projectScanService: dependencies.projectScanService))
        default:
            workflowActions.exitWorkflow()
            return AnyView(EmptyView())
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
        case WorkflowScreenID.manualAuditOverview:
            if project.workflowStatus == .completed {
                show(.projectCompletion, for: project)
                return
            }
            show(.manualAudit, for: project, startAtLastReviewed: startAtLastReviewed)
        default:
            resume(project: project, startAtLastReviewed: startAtLastReviewed)
        }
    }

    func resume(project: Project, startAtLastReviewed: Bool = false) {
        project.normalizeWorkflowStatus()
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
