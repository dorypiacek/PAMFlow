//
//  IncludedWorkflowModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import SwiftUI

/// Feature module for passive acoustic monitoring projects.
@MainActor
final class PAMWorkflowModule: BaseIncludedWorkflowModule {
    init() {
        super.init(
            configuration: ModuleConfiguration(
                details: PAMModuleConfiguration.details,
                fileConfiguration: PAMModuleConfiguration.files,
                setupConfiguration: PAMModuleConfiguration.makeSetupConfiguration
            ),
            capabilities: IncludedWorkflowCapabilities(usesPAMGuard: true, requiresSharkTrack: false)
        )
    }
}

/// Feature module for baited remote underwater video projects and related RUV workflows.
@MainActor
final class BRUVWorkflowModule: BaseIncludedWorkflowModule {
    init(projectType: BRUVProjectType) {
        let details = BRUVModuleConfiguration.details(for: projectType)
        super.init(
            configuration: ModuleConfiguration(
                details: details,
                fileConfiguration: BRUVModuleConfiguration.files,
                setupConfiguration: { BRUVModuleConfiguration.makeSetupConfiguration(for: projectType) }
            ),
            capabilities: IncludedWorkflowCapabilities(usesPAMGuard: false, requiresSharkTrack: true)
        )
    }
}

@MainActor
class BaseIncludedWorkflowModule: FeatureModule {
    private let configuration: ModuleConfiguration
    let capabilities: IncludedWorkflowCapabilities

    var details: ModuleDetails {
        configuration.details
    }

    fileprivate var projectSetupConfiguration: ProjectSetupConfiguration {
        configuration.setupConfiguration()
    }

    init(
        configuration: ModuleConfiguration,
        capabilities: IncludedWorkflowCapabilities
    ) {
        self.configuration = configuration
        self.capabilities = capabilities
    }

    func makeCoordinator(context: ModuleContext) -> ModuleCoordinating {
        IncludedWorkflowCoordinator(
            module: self,
            appCoordinator: context.appCoordinator,
            dependencies: context.dependencies
        )
    }
}

struct IncludedWorkflowCapabilities {
    let usesPAMGuard: Bool
    let requiresSharkTrack: Bool
}

enum IncludedWorkflowScreenID {
    static let scanProject = "scan_project"
    static let projectOverview = "project_overview"
    static let sharkTrackProcessing = "sharktrack_processing"
    static let manualAudit = "manual_audit"
    static let manualAuditOverview = "manual_audit_overview"
    static let pamguardSetup = "pamguard_setup"
    static let pamguardWaiting = "pamguard_waiting"
    static let pamguardProcessing = "pamguard_processing"
    static let projectCompletion = "project_completion"
}

enum IncludedWorkflowScreen {
    case scanProject
    case projectOverview
    case sharkTrackProcessing
    case manualAudit
    case manualAuditOverview
    case pamguardSetup
    case pamguardWaiting
    case pamguardProcessing
    case projectCompletion

    var id: String {
        switch self {
        case .scanProject:
            IncludedWorkflowScreenID.scanProject
        case .projectOverview:
            IncludedWorkflowScreenID.projectOverview
        case .sharkTrackProcessing:
            IncludedWorkflowScreenID.sharkTrackProcessing
        case .manualAudit:
            IncludedWorkflowScreenID.manualAudit
        case .manualAuditOverview:
            IncludedWorkflowScreenID.manualAuditOverview
        case .pamguardSetup:
            IncludedWorkflowScreenID.pamguardSetup
        case .pamguardWaiting:
            IncludedWorkflowScreenID.pamguardWaiting
        case .pamguardProcessing:
            IncludedWorkflowScreenID.pamguardProcessing
        case .projectCompletion:
            IncludedWorkflowScreenID.projectCompletion
        }
    }
}

@MainActor
private final class IncludedWorkflowCoordinator: ModuleCoordinating {
    var moduleID: ModuleID {
        module.details.id
    }

    private let module: BaseIncludedWorkflowModule
    private let appCoordinator: AppCoordinating
    private let dependencies: Dependencies

    init(module: BaseIncludedWorkflowModule, appCoordinator: AppCoordinating, dependencies: Dependencies) {
        self.module = module
        self.appCoordinator = appCoordinator
        self.dependencies = dependencies
    }

    func startProject() -> AnyView {
        AnyView(
            ProjectSetupView(
                viewModel: BaseProjectSetupViewModel(
                    configuration: module.projectSetupConfiguration,
                    projectFileService: dependencies.projectFileService,
                    fileSelectionService: dependencies.fileSelectionService
                )
            )
        )
    }

    func makeScreen(for route: ModuleScreenRoute) -> AnyView {
        // TODO: - Move these screen factories into the concrete module coordinators.
        switch route.screenID {
        case IncludedWorkflowScreenID.scanProject:
            AnyView(ScanProjectView(projectID: route.projectID))
        case IncludedWorkflowScreenID.projectOverview:
            AnyView(
                NewProjectOverviewView(
                    projectID: route.projectID,
                    projectScanService: dependencies.projectScanService
                )
            )
        case IncludedWorkflowScreenID.sharkTrackProcessing:
            AnyView(SharkTrackProcessingView(projectID: route.projectID))
        case IncludedWorkflowScreenID.manualAudit:
            AnyView(
                ManualAuditView(
                    projectID: route.projectID,
                    startAtLastReviewed: route.startAtLastReviewed,
                    projectScanService: dependencies.projectScanService,
                    audioPreviewCacheService: dependencies.audioPreviewCacheService
                )
            )
        case IncludedWorkflowScreenID.manualAuditOverview:
            AnyView(
                ManualAuditOverviewView(
                    projectID: route.projectID,
                    projectScanService: dependencies.projectScanService
                )
            )
        case IncludedWorkflowScreenID.pamguardSetup:
            AnyView(
                PAMGuardSetupView(
                    projectID: route.projectID,
                    projectScanService: dependencies.projectScanService,
                    preparationService: dependencies.pamGuardPreparationService
                )
            )
        case IncludedWorkflowScreenID.pamguardWaiting:
            AnyView(PAMGuardWaitingView(projectID: route.projectID))
        case IncludedWorkflowScreenID.pamguardProcessing:
            AnyView(
                PAMGuardProcessingView(
                    projectID: route.projectID,
                    projectScanService: dependencies.projectScanService,
                    processingService: dependencies.pamGuardDetectionProcessingService
                )
            )
        case IncludedWorkflowScreenID.projectCompletion:
            AnyView(
                ProjectCompletionView(
                    projectID: route.projectID,
                    projectScanService: dependencies.projectScanService
                )
            )
        default:
            AnyView(ProjectSelectionView())
        }
    }

    func previousRoute(for route: ModuleScreenRoute) -> AppRoute {
        switch route.screenID {
        case IncludedWorkflowScreenID.scanProject:
            .dataTypeSelection
        case IncludedWorkflowScreenID.projectOverview:
            moduleRoute(.scanProject, projectID: route.projectID)
        case IncludedWorkflowScreenID.sharkTrackProcessing:
            moduleRoute(.projectOverview, projectID: route.projectID)
        case IncludedWorkflowScreenID.manualAudit:
            moduleRoute(.projectOverview, projectID: route.projectID)
        case IncludedWorkflowScreenID.manualAuditOverview:
            moduleRoute(.manualAudit, projectID: route.projectID, startAtLastReviewed: true)
        case IncludedWorkflowScreenID.pamguardSetup:
            moduleRoute(.manualAuditOverview, projectID: route.projectID)
        case IncludedWorkflowScreenID.pamguardWaiting:
            moduleRoute(.pamguardSetup, projectID: route.projectID)
        case IncludedWorkflowScreenID.pamguardProcessing:
            moduleRoute(.pamguardWaiting, projectID: route.projectID)
        case IncludedWorkflowScreenID.projectCompletion:
            moduleRoute(.manualAuditOverview, projectID: route.projectID)
        default:
            .projectSelection
        }
    }

    func openNextStep(for project: Project, from route: AppRoute, startAtLastReviewed: Bool = false) {
        guard case .moduleScreen(let screen) = route else {
            openLatestProject(project, startAtLastReviewed: startAtLastReviewed)
            return
        }

        switch screen.screenID {
        case IncludedWorkflowScreenID.projectOverview:
            openNextFromProjectOverview(project)
        case IncludedWorkflowScreenID.manualAuditOverview:
            openNextFromManualAuditOverview(project, startAtLastReviewed: startAtLastReviewed)
        case IncludedWorkflowScreenID.pamguardWaiting:
            open(.pamguardProcessing, for: project)
        default:
            openLatestProject(project, startAtLastReviewed: startAtLastReviewed)
        }
    }

    func openLatestProject(_ project: Project, startAtLastReviewed: Bool = false) {
        switch project.workflowStatus {
        case .created, .scanInProgress:
            open(.scanProject, for: project)
        case .scanCompleted:
            openAfterScan(project)
        case .manualAuditInProgress:
            open(.manualAudit, for: project, startAtLastReviewed: startAtLastReviewed)
        case .manualAuditCompleted:
            open(.manualAuditOverview, for: project)
        case .pamguardSetupReady:
            openAfterPAMGuardSetupReady(project)
        case .processingProjectCreated:
            openAfterProcessingProjectCreated(project)
        case .processingRunImported:
            openAfterProcessingRunImported(project)
        case .runOverviewCompleted:
            openAfterRunOverviewCompleted(project)
        case .detectionReviewInProgress:
            openAfterDetectionReviewStarted(project, startAtLastReviewed: startAtLastReviewed)
        case .completed:
            open(.projectCompletion, for: project)
        }
    }

    func openReadOnlyProject(_ project: Project) {
        open(.projectCompletion, for: project)
    }

    private func openAfterScan(_ project: Project) {
        guard module.capabilities.requiresSharkTrack else {
            open(.projectOverview, for: project)
            return
        }
        open(.sharkTrackProcessing, for: project)
    }

    private func openAfterPAMGuardSetupReady(_ project: Project) {
        guard module.capabilities.usesPAMGuard else {
            open(.manualAuditOverview, for: project)
            return
        }
        open(.pamguardSetup, for: project)
    }

    private func openAfterProcessingProjectCreated(_ project: Project) {
        guard module.capabilities.requiresSharkTrack else {
            open(.pamguardWaiting, for: project)
            return
        }
        if hasReviewItems(project) {
            open(.manualAudit, for: project)
        } else {
            open(.manualAuditOverview, for: project)
        }
    }

    private func openAfterProcessingRunImported(_ project: Project) {
        guard module.capabilities.usesPAMGuard else {
            open(.projectOverview, for: project)
            return
        }
        open(.manualAuditOverview, for: project)
    }

    private func openAfterRunOverviewCompleted(_ project: Project) {
        guard module.capabilities.usesPAMGuard else {
            open(.projectOverview, for: project)
            return
        }
        open(.manualAudit, for: project)
    }

    private func openAfterDetectionReviewStarted(_ project: Project, startAtLastReviewed: Bool) {
        guard module.capabilities.usesPAMGuard else {
            open(.projectOverview, for: project)
            return
        }
        open(.manualAudit, for: project, startAtLastReviewed: startAtLastReviewed)
    }

    private func openNextFromProjectOverview(_ project: Project) {
        if module.capabilities.usesPAMGuard, project.workflowStatus == .manualAuditCompleted {
            open(.pamguardSetup, for: project)
            return
        }

        guard project.workflowStatus == .scanCompleted else {
            openLatestProject(project)
            return
        }

        guard module.capabilities.requiresSharkTrack else {
            project.workflowStatus = .manualAuditInProgress
            open(.manualAudit, for: project)
            return
        }

        open(.sharkTrackProcessing, for: project)
    }

    private func openNextFromManualAuditOverview(_ project: Project, startAtLastReviewed: Bool) {
        guard module.capabilities.usesPAMGuard, project.workflowStatus == .processingProjectCreated else {
            openLatestProject(project, startAtLastReviewed: startAtLastReviewed)
            return
        }

        open(.pamguardSetup, for: project)
    }

    private func open(_ screen: IncludedWorkflowScreen, for project: Project, startAtLastReviewed: Bool = false) {
        project.lastOpenedAt = .now
        appCoordinator.openModuleScreen(
            ModuleScreenRoute(
                moduleID: module.details.id,
                screenID: screen.id,
                projectID: project.id,
                startAtLastReviewed: startAtLastReviewed
            )
        )
    }

    private func moduleRoute(
        _ screen: IncludedWorkflowScreen,
        projectID: UUID,
        startAtLastReviewed: Bool = false
    ) -> AppRoute {
        .moduleScreen(
            ModuleScreenRoute(
                moduleID: module.details.id,
                screenID: screen.id,
                projectID: projectID,
                startAtLastReviewed: startAtLastReviewed
            )
        )
    }

    private func hasReviewItems(_ project: Project) -> Bool {
        (try? dependencies.projectScanService.loadSummary(for: project).fileCount) ?? 0 > 0
    }
}

extension WorkflowModule {
    var moduleID: ModuleID {
        ModuleID(rawValue: id)
    }
}
