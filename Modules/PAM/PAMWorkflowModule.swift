//
//  PAMWorkflowModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import UI
import Core
import SwiftData
import SwiftUI

/// Feature module for passive acoustic monitoring projects.
@MainActor
public final class PAMWorkflowModule: FeatureModule {
    public let details = PAMModuleConfiguration.details

    public init() {}

    public func makeCoordinator(context: ModuleContext) -> ModuleCoordinating {
        WorkflowCoordinator(
            workflowActions: context.workflowActions,
            dependencies: PAMWorkflowDependencies(sharedDependencies: context.dependencies)
        )
    }

    /// Prepares the first likely audio file for fast playback from the project list.
    public func preheatProjectPreviews(project: Project, modelContext: ModelContext, dependencies: SharedAppDependencies) {
        guard let inputFolderURL = project.inputFolderURL else { return }

        do {
            var summary = try dependencies.projectScanService.loadSummary(for: project)
            summary.files.sort { suspicionScore($0) > suspicionScore($1) }
            let audioFiles = summary.files.filter { isSupportedAudioPath($0.relativePath) }
            guard let file = firstUndecidedFile(in: audioFiles, project: project, modelContext: modelContext) ?? audioFiles.first else {
                return
            }

            let url = inputFolderURL.appendingPathComponent(file.relativePath)
            AudioPreviewCacheService().preheat(
                url: url,
                securityScopedURL: inputFolderURL,
                clipStartSeconds: nil,
                clipDurationSeconds: nil
            )
        } catch {
            AppLog.info("PAM project selection preview preheat failed for '\(project.name)': \(error.localizedDescription)")
        }
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
        if files.contains(where: { $0.pamDetectionStatus == PAMScanStatus.pamguard }) {
            files.sort {
                ($0.pamDetectionID ?? Int.max) < ($1.pamDetectionID ?? Int.max)
            }
        }
    }

    private func firstUndecidedFile(
        in files: [ProjectScanFile],
        project: Project,
        modelContext: ModelContext
    ) -> ProjectScanFile? {
        files.first { file in
            let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
            let descriptor = FetchDescriptor<ManualAuditDecision>(
                predicate: #Predicate { decision in
                    decision.id == id
                }
            )
            return (try? modelContext.fetch(descriptor).first) == nil
        }
    }

    private func suspicionScore(_ file: ProjectScanFile) -> Double {
        var score = 0.0

        if !file.readable { score += 1_000 }
        if file.qualityFlag.lowercased() != "ok" { score += 100 }
        score += Double(file.qualityReasons.count) * 25
        score += (file.clippingPercent ?? 0) * 10
        score += (file.nearZeroPercent ?? 0)

        if let rms = file.rmsDBFS, rms < -70 {
            score += 40
        }

        if file.durationSeconds == nil {
            score += 30
        }

        return score
    }

    private func isSupportedAudioPath(_ path: String) -> Bool {
        PAMMediaFileExtensions.audio.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
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
                statusTitle: Strings.WorkflowStatus.scanCompleted,
                primaryActionTitle: Strings.WorkflowStatus.continueToOverview,
                lastCompletedStepTitle: Strings.WorkflowStatus.scanCompleted
            )
        case .manualAuditInProgress, .inProgress:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.manualAuditInProgress,
                primaryActionTitle: Strings.WorkflowStatus.continueManualAudit,
                lastCompletedStepTitle: "\(Strings.ProjectSelection.manualAuditProgressPrefix) \(auditProgressText)"
            )
        case .manualAuditCompleted:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.manualAuditCompleted,
                primaryActionTitle: Strings.WorkflowStatus.openAuditOverview,
                lastCompletedStepTitle: Strings.WorkflowStatus.manualAuditCompleted
            )
        case .pamguardSetupReady:
            ProjectSelectionPresentation(
                statusTitle: PAMStrings.Overview.readyForPamguard,
                primaryActionTitle: PAMStrings.Overview.goToPamguardSetup,
                lastCompletedStepTitle: Strings.WorkflowStatus.manualAuditCompleted
            )
        case .processingProjectCreated:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.processingProjectCreated,
                primaryActionTitle: Strings.WorkflowStatus.importProcessingRun,
                lastCompletedStepTitle: Strings.WorkflowStatus.processingProjectCreated
            )
        case .processingRunImported:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.processingRunImported,
                primaryActionTitle: Strings.WorkflowStatus.openRunOverview,
                lastCompletedStepTitle: Strings.WorkflowStatus.processingRunImported
            )
        case .runOverviewCompleted:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.runOverviewCompleted,
                primaryActionTitle: Strings.WorkflowStatus.continueDetectionReview,
                lastCompletedStepTitle: Strings.WorkflowStatus.runOverviewCompleted
            )
        case .detectionReviewInProgress:
            ProjectSelectionPresentation(
                statusTitle: Strings.WorkflowStatus.detectionReviewInProgress,
                primaryActionTitle: Strings.WorkflowStatus.continueDetectionReview,
                lastCompletedStepTitle: "\(Strings.ProjectSelection.detectionReviewProgressPrefix) \(auditProgressText)"
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

/// Service dependencies required by the PAM workflow module.
@MainActor
private struct PAMWorkflowDependencies {
    let projectFileService: ProjectFileServicing
    let projectScanService: ProjectScanServicing
    let audioPreviewCacheService: AudioPreviewCacheServicing
    let pamGuardPreparationService: PAMGuardPreparationServicing
    let pamGuardDetectionProcessingService: PAMGuardDetectionProcessingServicing
    let fileSelectionService: FileSelecting

    init(
        projectFileService: ProjectFileServicing,
        projectScanService: ProjectScanServicing,
        audioPreviewCacheService: AudioPreviewCacheServicing,
        pamGuardPreparationService: PAMGuardPreparationServicing,
        pamGuardDetectionProcessingService: PAMGuardDetectionProcessingServicing,
        fileSelectionService: FileSelecting
    ) {
        self.projectFileService = projectFileService
        self.projectScanService = projectScanService
        self.audioPreviewCacheService = audioPreviewCacheService
        self.pamGuardPreparationService = pamGuardPreparationService
        self.pamGuardDetectionProcessingService = pamGuardDetectionProcessingService
        self.fileSelectionService = fileSelectionService
    }

    init(sharedDependencies: SharedAppDependencies) {
        self.init(
            projectFileService: sharedDependencies.projectFileService,
            projectScanService: sharedDependencies.projectScanService,
            audioPreviewCacheService: AudioPreviewCacheService(),
            pamGuardPreparationService: PAMGuardPreparationService(),
            pamGuardDetectionProcessingService: PAMGuardDetectionProcessingService(),
            fileSelectionService: sharedDependencies.fileSelectionService
        )
    }
}

private enum WorkflowScreenID {
    static let scanProject = "scan_project"
    static let projectOverview = "project_overview"
    static let manualAudit = "manual_audit"
    static let manualAuditOverview = "manual_audit_overview"
    static let pamguardSetup = "pamguard_setup"
    static let pamguardWaiting = "pamguard_waiting"
    static let pamguardProcessing = "pamguard_processing"
    static let projectCompletion = "project_completion"
}

private enum WorkflowScreen {
    case scanProject
    case projectOverview
    case manualAudit
    case manualAuditOverview
    case pamguardSetup
    case pamguardWaiting
    case pamguardProcessing
    case projectCompletion

    var id: String {
        switch self {
        case .scanProject:
            WorkflowScreenID.scanProject
        case .projectOverview:
            WorkflowScreenID.projectOverview
        case .manualAudit:
            WorkflowScreenID.manualAudit
        case .manualAuditOverview:
            WorkflowScreenID.manualAuditOverview
        case .pamguardSetup:
            WorkflowScreenID.pamguardSetup
        case .pamguardWaiting:
            WorkflowScreenID.pamguardWaiting
        case .pamguardProcessing:
            WorkflowScreenID.pamguardProcessing
        case .projectCompletion:
            WorkflowScreenID.projectCompletion
        }
    }
}

@MainActor
private final class WorkflowCoordinator: ModuleCoordinating {
    let moduleID = PAMModuleConfiguration.details.id
    private(set) var currentScreen: AnyView = AnyView(EmptyView())

    private let workflowActions: WorkflowActionHandling
    private let dependencies: PAMWorkflowDependencies
    private var currentRoute: ModuleScreenRoute?

    init(workflowActions: WorkflowActionHandling, dependencies: PAMWorkflowDependencies) {
        self.workflowActions = workflowActions
        self.dependencies = dependencies
    }

    func startProject() {
        currentRoute = nil
        currentScreen = AnyView(
            ProjectSetupView(
                viewModel: BaseProjectSetupViewModel(
                    configuration: PAMModuleConfiguration.makeSetupConfiguration(),
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
                    supportedFileExtensions: PAMMediaFileExtensions.audio,
                    scanAnalyzer: PAMAudioScanAnalyzer()
                )
            )
        case WorkflowScreenID.projectOverview:
            return AnyView(
                NewProjectOverviewView(
                    projectID: route.projectID,
                    viewModel: PAMProjectOverviewViewModel(
                        projectScanService: dependencies.projectScanService,
                        audioPreviewCacheService: dependencies.audioPreviewCacheService
                    )
                )
            )
        case WorkflowScreenID.manualAudit:
            let viewModel = PAMManualAuditViewModel(
                projectScanService: dependencies.projectScanService,
                audioPreviewCacheService: dependencies.audioPreviewCacheService
            )
            return AnyView(
                ManualAuditView(
                    projectID: route.projectID,
                    startAtLastReviewed: route.startAtLastReviewed,
                    viewModel: viewModel
                ) { _, project, file in
                    PAMManualAuditPreview(viewModel: viewModel, project: project, file: file)
                }
            )
        case WorkflowScreenID.manualAuditOverview:
            return AnyView(
                ManualAuditOverviewView(
                    projectID: route.projectID,
                    viewModel: PAMManualAuditOverviewViewModel(
                        projectID: route.projectID,
                        projectScanService: dependencies.projectScanService,
                        audioPreviewCacheService: dependencies.audioPreviewCacheService
                    )
                )
            )
        case WorkflowScreenID.pamguardSetup:
            return AnyView(
                PAMGuardSetupView(
                    projectID: route.projectID,
                    projectScanService: dependencies.projectScanService,
                    preparationService: dependencies.pamGuardPreparationService,
                    workflowActions: workflowActions
                )
            )
        case WorkflowScreenID.pamguardWaiting:
            return AnyView(PAMGuardWaitingView(projectID: route.projectID, workflowActions: workflowActions))
        case WorkflowScreenID.pamguardProcessing:
            return AnyView(
                PAMGuardProcessingView(
                    projectID: route.projectID,
                    projectScanService: dependencies.projectScanService,
                    processingService: dependencies.pamGuardDetectionProcessingService,
                    workflowActions: workflowActions
                )
            )
        case WorkflowScreenID.projectCompletion:
            return AnyView(PAMProjectCompletionView(projectID: route.projectID, projectScanService: dependencies.projectScanService))
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
        case WorkflowScreenID.manualAudit:
            show(.projectOverview, projectID: currentRoute.projectID)
        case WorkflowScreenID.manualAuditOverview:
            show(.manualAudit, projectID: currentRoute.projectID, startAtLastReviewed: true)
        case WorkflowScreenID.pamguardSetup:
            show(.manualAuditOverview, projectID: currentRoute.projectID)
        case WorkflowScreenID.pamguardWaiting:
            show(.pamguardSetup, projectID: currentRoute.projectID)
        case WorkflowScreenID.pamguardProcessing:
            show(.pamguardWaiting, projectID: currentRoute.projectID)
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
            showNextFromManualAuditOverview(project, startAtLastReviewed: startAtLastReviewed)
        case WorkflowScreenID.pamguardWaiting:
            show(.pamguardProcessing, for: project)
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
            show(.projectOverview, for: project)
        case .manualAuditInProgress:
            show(.manualAudit, for: project, startAtLastReviewed: startAtLastReviewed)
        case .manualAuditCompleted:
            show(.manualAuditOverview, for: project)
        case .pamguardSetupReady:
            show(.pamguardSetup, for: project)
        case .processingProjectCreated:
            show(.pamguardWaiting, for: project)
        case .processingRunImported:
            show(.manualAuditOverview, for: project)
        case .runOverviewCompleted, .detectionReviewInProgress:
            show(.manualAudit, for: project, startAtLastReviewed: startAtLastReviewed)
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
        if project.workflowStatus == .manualAuditCompleted {
            show(.pamguardSetup, for: project)
            return
        }

        guard project.workflowStatus == .scanCompleted else {
            resume(project: project)
            return
        }

        project.workflowStatus = .manualAuditInProgress
        show(.manualAudit, for: project)
    }

    private func showNextFromManualAuditOverview(_ project: Project, startAtLastReviewed: Bool) {
        guard project.workflowStatus == .pamguardSetupReady else {
            resume(project: project, startAtLastReviewed: startAtLastReviewed)
            return
        }

        show(.pamguardSetup, for: project)
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
