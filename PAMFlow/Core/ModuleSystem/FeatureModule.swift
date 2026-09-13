//
//  FeatureModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Foundation
import SwiftUI

/// A selectable workflow capability included in a particular build.
@MainActor
protocol FeatureModule {
    var details: ModuleDetails { get }

    func makeCoordinator(context: ModuleContext) -> ModuleCoordinating
}

/// Workflow commands available to module-owned screens and ViewModels.
@MainActor
protocol WorkflowActionHandling: AnyObject {
    /// Opens the setup entry point for a module.
    func openModule(moduleID: ModuleID)
    /// Opens the project library.
    func openProjectSelection()
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
    let dependencies: Dependencies
    let workflowActions: WorkflowActionHandling

    init(dependencies: Dependencies, workflowActions: WorkflowActionHandling) {
        self.dependencies = dependencies
        self.workflowActions = workflowActions
    }
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
