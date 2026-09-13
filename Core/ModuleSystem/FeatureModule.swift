//
//  FeatureModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Foundation
import SwiftData
import SwiftUI

/// A selectable workflow capability included in a particular build.
@MainActor
protocol FeatureModule {
    var details: ModuleDetails { get }

    func makeCoordinator(context: ModuleContext) -> ModuleCoordinating
    /// Gives the module a chance to prepare previews for a recently used project.
    func preheatProjectPreviews(project: Project, modelContext: ModelContext, dependencies: SharedAppDependencies)
    /// Returns row presentation for a project owned by this module.
    func projectSelectionPresentation(
        for project: Project,
        folderExists: Bool,
        auditProgressText: String
    ) -> ProjectSelectionPresentation
}

extension FeatureModule {
    func preheatProjectPreviews(project: Project, modelContext: ModelContext, dependencies: SharedAppDependencies) {}

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
        switch status {
        case .created:
            Strings.WorkflowStatus.created
        case .inProgress:
            Strings.WorkflowStatus.inProgress
        case .completed:
            Strings.WorkflowStatus.completed
        default:
            status.rawValue
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
}

/// Localized project-list text provided by a module for its own workflow states.
struct ProjectSelectionPresentation: Equatable, Sendable {
    let statusTitle: String
    let primaryActionTitle: String
    let lastCompletedStepTitle: String
}

/// Workflow commands available to module-owned screens and ViewModels.
@MainActor
protocol WorkflowActionHandling: AnyObject {
    /// Returns to the previous workflow step.
    func goToPreviousStep(for project: Project)
    /// Advances to the next workflow step.
    func goToNextStep(for project: Project, startAtLastReviewed: Bool)
    /// Leaves the active module workflow and returns to the host app.
    func exitWorkflow()
}

extension WorkflowActionHandling {
    /// Advances to the next workflow step from the current route.
    func goToNextStep(for project: Project) {
        goToNextStep(for: project, startAtLastReviewed: false)
    }
}

/// App services exposed to feature modules through a single context object.
@MainActor
struct ModuleContext {
    let dependencies: SharedAppDependencies
    let workflowActions: WorkflowActionHandling

    init(dependencies: SharedAppDependencies, workflowActions: WorkflowActionHandling) {
        self.dependencies = dependencies
        self.workflowActions = workflowActions
    }
}

/// App-level services that are safe for every module to depend on.
@MainActor
protocol SharedAppDependencies {
    /// Creates, opens, and removes project folders managed by the host app.
    var projectFileService: ProjectFileServicing { get }
    /// Scans project folders and persists generic scan summaries.
    var projectScanService: ProjectScanServicing { get }
    /// Presents host file-selection panels for project setup and export.
    var fileSelectionService: FileSelecting { get }
}

/// Coordinator owned by a feature module.
@MainActor
protocol ModuleCoordinating: AnyObject {
    var moduleID: ModuleID { get }
    var currentScreen: AnyView { get }

    func startProject()
    func goBack()
    func goToNextStep(for project: Project, startAtLastReviewed: Bool)
    func resume(project: Project, startAtLastReviewed: Bool)
    func openReadOnlyProject(_ project: Project)
}

extension ModuleCoordinating {
    func goToNextStep(for project: Project, startAtLastReviewed: Bool = false) {
        resume(project: project, startAtLastReviewed: startAtLastReviewed)
    }

    func resume(project: Project) {
        resume(project: project, startAtLastReviewed: false)
    }
}
