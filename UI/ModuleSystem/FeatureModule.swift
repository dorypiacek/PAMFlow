//
//  FeatureModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Foundation
import Core
import SwiftData
import SwiftUI

/// A selectable workflow capability included in a particular build.
@MainActor
public protocol FeatureModule {
    var details: ModuleDetails { get }

    func makeCoordinator(context: ModuleContext) -> ModuleCoordinating
    /// Gives the module a chance to prepare previews for a recently used project.
    func preheatProjectPreviews(project: Project, modelContext: ModelContext, dependencies: SharedAppDependencies)
    /// Returns progress for the module-owned review queue shown on project selection.
    func projectSelectionProgress(
        for project: Project,
        modelContext: ModelContext,
        projectScanService: ProjectScanServicing
    ) -> ProjectSelectionProgress
    /// Returns row presentation for a project owned by this module.
    func projectSelectionPresentation(
        for project: Project,
        folderExists: Bool,
        auditProgressText: String
    ) -> ProjectSelectionPresentation
}

public extension FeatureModule {
    func preheatProjectPreviews(project: Project, modelContext: ModelContext, dependencies: SharedAppDependencies) {}

    func projectSelectionProgress(
        for project: Project,
        modelContext: ModelContext,
        projectScanService: ProjectScanServicing
    ) -> ProjectSelectionProgress {
        let summary = try? projectScanService.loadSummary(for: project)
        return ProjectSelectionProgress(project: project, modelContext: modelContext, files: summary?.files ?? [])
    }

    func projectSelectionPresentation(
        for project: Project,
        folderExists: Bool,
        auditProgressText: String
    ) -> ProjectSelectionPresentation {
        let title = defaultStatusTitle(for: project.workflowStatus)
        if folderExists {
            return ProjectSelectionPresentation(
                statusTitle: title,
                primaryActionTitle: Strings.WorkflowStatus.viewProject,
                lastCompletedStepTitle: title
            )
        } else {
            return ProjectSelectionPresentation(
                statusTitle: title,
                primaryActionTitle: Strings.WorkflowStatus.viewProject,
                lastCompletedStepTitle: title
            )
        }
    }

    private func defaultStatusTitle(for status: ProjectWorkflowStatus) -> String {
        status.genericDisplayTitle
    }
}

/// Review progress for the module-owned queue shown on project selection.
public struct ProjectSelectionProgress: Equatable, Sendable {
    public let reviewed: Int
    public let total: Int
    public let displayPosition: Int

    public init(reviewed: Int, total: Int, displayPosition: Int) {
        self.reviewed = reviewed
        self.total = total
        self.displayPosition = displayPosition
    }

    public init(project: Project, modelContext: ModelContext, files: [ProjectScanFile]) {
        let projectID = project.id
        let currentFilePaths = files.map(\.relativePath)
        let currentFilePathSet = Set(currentFilePaths)
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        let decisions = (try? modelContext.fetch(descriptor)) ?? []
        let reviewedPaths = Set(decisions.map(\.fileRelativePath).filter {
            currentFilePathSet.isEmpty || currentFilePathSet.contains($0)
        })
        let total = currentFilePaths.count
        let reviewed = min(reviewedPaths.count, total == 0 ? reviewedPaths.count : total)
        let firstUndecidedIndex = currentFilePaths.firstIndex { !reviewedPaths.contains($0) }
        let displayPosition = total == 0 ? 0 : min((firstUndecidedIndex ?? max(reviewed - 1, 0)) + 1, total)
        self.init(reviewed: reviewed, total: total, displayPosition: displayPosition)
    }
}

/// Localized project-list text provided by a module for its own workflow states.
public struct ProjectSelectionPresentation: Equatable, Sendable {
    public let statusTitle: String
    public let primaryActionTitle: String
    public let lastCompletedStepTitle: String

    public init(statusTitle: String, primaryActionTitle: String, lastCompletedStepTitle: String) {
        self.statusTitle = statusTitle
        self.primaryActionTitle = primaryActionTitle
        self.lastCompletedStepTitle = lastCompletedStepTitle
    }
}

/// Workflow commands available to module-owned screens and ViewModels.
@MainActor
public protocol WorkflowActionHandling: AnyObject {
    /// Returns to the previous workflow step.
    func goToPreviousStep(for project: Project)
    /// Advances to the next workflow step.
    func goToNextStep(for project: Project, startAtLastReviewed: Bool)
    /// Leaves the active module workflow and returns to the host app.
    func exitWorkflow()
}

public extension WorkflowActionHandling {
    /// Advances to the next workflow step from the current route.
    func goToNextStep(for project: Project) {
        goToNextStep(for: project, startAtLastReviewed: false)
    }
}

/// App services exposed to feature modules through a single context object.
@MainActor
public struct ModuleContext {
    public let dependencies: SharedAppDependencies
    public let workflowActions: WorkflowActionHandling

    public init(dependencies: SharedAppDependencies, workflowActions: WorkflowActionHandling) {
        self.dependencies = dependencies
        self.workflowActions = workflowActions
    }
}

/// App-level services that are safe for every module to depend on.
@MainActor
public protocol SharedAppDependencies {
    /// Creates, opens, and removes project folders managed by the host app.
    var projectFileService: ProjectFileServicing { get }
    /// Scans project folders and persists generic scan summaries.
    var projectScanService: ProjectScanServicing { get }
    /// Presents host file-selection panels for project setup and export.
    var fileSelectionService: FileSelecting { get }
}

/// Coordinator owned by a feature module.
@MainActor
public protocol ModuleCoordinating: AnyObject {
    var moduleID: ModuleID { get }
    var currentScreen: AnyView { get }

    func startProject()
    func goBack()
    func goToNextStep(for project: Project, startAtLastReviewed: Bool)
    func resume(project: Project, startAtLastReviewed: Bool)
    func openReadOnlyProject(_ project: Project)
}

public extension ModuleCoordinating {
    func goToNextStep(for project: Project, startAtLastReviewed: Bool = false) {
        resume(project: project, startAtLastReviewed: startAtLastReviewed)
    }

    func resume(project: Project) {
        resume(project: project, startAtLastReviewed: false)
    }
}
