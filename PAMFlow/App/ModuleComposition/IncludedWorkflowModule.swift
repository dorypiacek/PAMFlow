//
//  IncludedWorkflowModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import SwiftUI

// TODO: - Replace this temporary adapter with dedicated PAM, BRUV, and RUV module targets.

/// Feature module for passive acoustic monitoring projects.
@MainActor
final class PAMWorkflowModule: BaseIncludedWorkflowModule {
    init() {
        let details = ModuleDetails(
            id: ModuleID(rawValue: WorkflowModuleID.pamAudio),
            name: Strings.DataTypeSelection.pamAudioTitle,
            subtitle: Strings.DataTypeSelection.pamAudioSubtitle,
            iconName: Icons.audio,
            projectNamePrefix: "PAM",
            libraryFolderName: Strings.WorkflowModule.audioFolder,
            supportedFileExtensions: MediaFileExtensions.wavAudio
        )
        super.init(
            details: details,
            setupConfigurationFactory: PAMProjectSetupConfigurationFactory(details: details),
            capabilities: IncludedWorkflowCapabilities(usesPAMGuard: true, requiresSharkTrack: false)
        )
    }
}

/// Feature module for baited remote underwater video projects.
@MainActor
final class BRUVWorkflowModule: BaseIncludedWorkflowModule {
    init() {
        let details = ModuleDetails(
            id: ModuleID(rawValue: WorkflowModuleID.bruvVideo),
            name: Strings.DataTypeSelection.bruvVideoTitle,
            subtitle: Strings.DataTypeSelection.bruvVideoSubtitle,
            iconName: Icons.video,
            projectNamePrefix: "BRUV",
            libraryFolderName: Strings.WorkflowModule.bruvVideoFolder,
            supportedFileExtensions: MediaFileExtensions.video
        )
        super.init(
            details: details,
            setupConfigurationFactory: VisualProjectSetupConfigurationFactory(details: details),
            capabilities: IncludedWorkflowCapabilities(usesPAMGuard: false, requiresSharkTrack: true)
        )
    }
}

/// Feature module for remote underwater image projects.
@MainActor
final class RUVWorkflowModule: BaseIncludedWorkflowModule {
    init() {
        let details = ModuleDetails(
            id: ModuleID(rawValue: WorkflowModuleID.ruvImages),
            name: Strings.DataTypeSelection.ruvImageTitle,
            subtitle: Strings.DataTypeSelection.ruvImageSubtitle,
            iconName: Icons.image,
            projectNamePrefix: "RUV",
            libraryFolderName: Strings.WorkflowModule.ruvImagesFolder,
            supportedFileExtensions: MediaFileExtensions.image
        )
        super.init(
            details: details,
            setupConfigurationFactory: VisualProjectSetupConfigurationFactory(details: details),
            capabilities: IncludedWorkflowCapabilities(usesPAMGuard: false, requiresSharkTrack: true)
        )
    }
}

@MainActor
class BaseIncludedWorkflowModule: FeatureModule {
    let details: ModuleDetails
    let capabilities: IncludedWorkflowCapabilities
    private let setupConfigurationFactory: ProjectSetupConfigurationFactory

    fileprivate var projectSetupConfiguration: ProjectSetupConfiguration {
        setupConfigurationFactory.makeConfiguration()
    }

    init(
        details: ModuleDetails,
        setupConfigurationFactory: ProjectSetupConfigurationFactory,
        capabilities: IncludedWorkflowCapabilities
    ) {
        self.details = details
        self.setupConfigurationFactory = setupConfigurationFactory
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
protocol ProjectSetupConfigurationFactory {
    func makeConfiguration() -> ProjectSetupConfiguration
}

@MainActor
struct PAMProjectSetupConfigurationFactory: ProjectSetupConfigurationFactory {
    let details: ModuleDetails

    func makeConfiguration() -> ProjectSetupConfiguration {
        ProjectSetupConfiguration(
            module: details,
            metadataUploadMessage: Strings.ProjectSetup.pamMetadataUploadMessage,
            metadataCacheKey: "pamflow.\(details.id.rawValue).metadata.csv.bookmark",
            requiredMetadataFields: fields,
            metadataSelectionFieldID: "opcode",
            isMetadataComplete: { values in
                !values.value(for: "opcode").trimmed.isEmpty &&
                    !values.value(for: "date").trimmed.isEmpty &&
                    !values.value(for: "date_retrieved").trimmed.isEmpty &&
                    !values.value(for: "location").trimmed.isEmpty &&
                    !values.value(for: "depth").trimmed.isEmpty
            },
            applyMetadata: applyMetadata
        )
    }

    private var fields: [ProjectMetadataField] {
        [
            ProjectMetadataField(id: "opcode", title: Strings.ProjectSetup.opcode, isRequired: true, csvAliases: ["opcode", "op code", "operation code"]),
            ProjectMetadataField(id: "date", title: Strings.ProjectSetup.dateDeployed, isRequired: true, valueType: .date, csvAliases: ["date deployed", "deployment date", "deploy date", "sample date", "date"]),
            ProjectMetadataField(id: "date_retrieved", title: Strings.ProjectSetup.dateRetrieved, isRequired: true, valueType: .date, csvAliases: ["date retrieved", "retrieval date", "retrieve date", "recovery date", "date recovered"]),
            ProjectMetadataField(id: "location", title: Strings.ProjectSetup.location, isRequired: true, csvAliases: ["location", "site", "station"]),
            ProjectMetadataField(id: "depth", title: Strings.ProjectSetup.depth, isRequired: true, valueType: .number, csvAliases: ["depth", "water depth"]),
            ProjectMetadataField(id: "bottom_type", title: Strings.ProjectSetup.bottomType, isRequired: false, csvAliases: ["bottom type", "substrate", "habitat"])
        ]
    }
}

@MainActor
struct VisualProjectSetupConfigurationFactory: ProjectSetupConfigurationFactory {
    let details: ModuleDetails

    func makeConfiguration() -> ProjectSetupConfiguration {
        ProjectSetupConfiguration(
            module: details,
            metadataUploadMessage: Strings.ProjectSetup.visualMetadataUploadMessage,
            metadataCacheKey: "pamflow.\(details.id.rawValue).metadata.csv.bookmark",
            requiredMetadataFields: fields,
            metadataSelectionFieldID: "opcode",
            isMetadataComplete: { values in
                !values.value(for: "opcode").trimmed.isEmpty &&
                    !values.value(for: "date").trimmed.isEmpty &&
                    !values.value(for: "location").trimmed.isEmpty &&
                    !values.value(for: "depth").trimmed.isEmpty
            },
            applyMetadata: applyMetadata
        )
    }

    private var fields: [ProjectMetadataField] {
        [
            ProjectMetadataField(id: "opcode", title: Strings.ProjectSetup.opcode, isRequired: true, csvAliases: ["opcode", "op code", "operation code"]),
            ProjectMetadataField(id: "date", title: Strings.ProjectSetup.date, isRequired: true, valueType: .date, csvAliases: ["date deployed", "deployment date", "deploy date", "sample date", "date"]),
            ProjectMetadataField(id: "location", title: Strings.ProjectSetup.location, isRequired: true, csvAliases: ["location", "site", "station"]),
            ProjectMetadataField(id: "depth", title: Strings.ProjectSetup.depth, isRequired: true, valueType: .number, csvAliases: ["depth", "water depth"]),
            ProjectMetadataField(id: "bottom_type", title: Strings.ProjectSetup.bottomType, isRequired: false, csvAliases: ["bottom type", "substrate", "habitat"]),
            ProjectMetadataField(id: "water_temperature", title: Strings.ProjectSetup.waterTemperature, isRequired: false, valueType: .number, csvAliases: ["water temperature", "temperature", "temp"])
        ]
    }
}

@MainActor
private func applyMetadata(_ values: ProjectMetadataValues, _ project: Project) {
    project.metadataOpcode = values.value(for: "opcode").trimmed.nilIfEmpty
    project.metadataDate = values.value(for: "date").trimmed.nilIfEmpty
    project.metadataDateRetrieved = values.value(for: "date_retrieved").trimmed.nilIfEmpty
    project.metadataLocation = values.value(for: "location").trimmed.nilIfEmpty
    project.metadataDepth = values.value(for: "depth").trimmed.nilIfEmpty
    project.metadataBottomType = values.value(for: "bottom_type").trimmed.nilIfEmpty
    project.metadataWaterTemperature = values.value(for: "water_temperature").trimmed.nilIfEmpty
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
