//
//  AppCoordinator.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation
import Observation

/// Navigation and global app actions exposed to feature models.
@MainActor
protocol AppCoordinating: AnyObject {
    var userProfile: UserProfile? { get }
    var route: AppRoute { get set }
    var selectedTheme: AppTheme { get set }
    var settingsErrorMessage: String? { get set }
    var dependencies: Dependencies { get }
    var moduleCatalog: ModuleCatalog { get }
    var canGoBack: Bool { get }
    var canGoHome: Bool { get }

    @discardableResult
    func saveUserName(_ name: String) -> Bool
    func signOut()
    func selectTheme(_ theme: AppTheme)
    func openDataTypeSelection()
    func openModule(moduleID: ModuleID)
    func openProjectSelection()
    func goHome()
    func goBack()
    func goToNextStep(for project: Project, startAtLastReviewed: Bool)
    func goToPreviousStep(for project: Project)
    func openReadOnlyProject(_ project: Project)
    func continueProject(_ project: Project)
}

extension AppCoordinating {
    func goToNextStep(for project: Project) {
        goToNextStep(for: project, startAtLastReviewed: false)
    }
}

@Observable
@MainActor
/// Coordinates app-wide state, user preferences, and top-level navigation.
///
/// `AppCoordinator` intentionally keeps screen-specific state out of the global
/// object. Feature screens own their local models and call these navigation
/// methods after durable state has been saved.
final class AppCoordinator: AppCoordinating, WorkflowActionHandling {
    var userProfile: UserProfile?
    var route: AppRoute
    var selectedTheme: AppTheme
    var settingsErrorMessage: String?
    var activeModuleCoordinator: ModuleCoordinating?
    var workflowRevision = 0

    let dependencies: Dependencies

    private let userProfileStore: UserProfileStoring
    private let appThemeStore: AppThemeStoring
    let moduleCatalog: ModuleCatalog

    init(
        userProfileStore: UserProfileStoring,
        appThemeStore: AppThemeStoring,
        dependencies: Dependencies,
        moduleCatalog: ModuleCatalog
    ) {
        self.userProfileStore = userProfileStore
        self.appThemeStore = appThemeStore
        self.dependencies = dependencies
        self.moduleCatalog = moduleCatalog
        let profile = userProfileStore.load()
        self.userProfile = profile
        self.selectedTheme = appThemeStore.load()
        self.route = profile == nil ? .welcome : .projectSelection
    }

    @discardableResult
    func saveUserName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let profile = UserProfile(name: trimmed)
        userProfileStore.save(profile)
        userProfile = profile
        route = .projectSelection
        return true
    }

    func signOut() {
        userProfileStore.delete()
        userProfile = nil
        route = .welcome
    }

    func selectTheme(_ theme: AppTheme) {
        selectedTheme = theme
        appThemeStore.save(theme)
    }
    
    var canGoBack: Bool {
        switch route {
        case .welcome, .projectSelection:
            false
        default:
            true
        }
    }

    var canGoHome: Bool {
        switch route {
        case .welcome, .projectSelection:
            false
        default:
            true
        }
    }

    func openDataTypeSelection() {
        route = .dataTypeSelection
    }

    func openModule(moduleID: ModuleID) {
        guard let module = moduleCatalog.module(for: moduleID) else {
            route = .projectSelection
            return
        }
        let coordinator = module.makeCoordinator(
            context: ModuleContext(dependencies: dependencies, workflowActions: self)
        )
        coordinator.startProject()
        activeModuleCoordinator = coordinator
        workflowRevision += 1
        route = .moduleWorkflow
    }

    func openProjectSelection() {
        activeModuleCoordinator = nil
        workflowRevision += 1
        route = .projectSelection
    }

    func goHome() {
        if route == .moduleWorkflow {
            exitWorkflow()
            return
        }

        activeModuleCoordinator = nil
        workflowRevision += 1
        route = userProfile == nil ? .welcome : .projectSelection
    }

    func exitWorkflow() {
        activeModuleCoordinator = nil
        workflowRevision += 1
        route = .projectSelection
    }

    func goBack() {
        switch route {
        case .welcome, .projectSelection:
            break
        case .dataTypeSelection:
            route = .projectSelection
        case .moduleWorkflow:
            activeModuleCoordinator?.goBack()
            workflowRevision += 1
        }
    }

    func goToNextStep(for project: Project, startAtLastReviewed: Bool = false) {
        project.lastOpenedAt = .now

        guard let module = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID)) else {
            openReadOnlyProject(project)
            return
        }

        if activeModuleCoordinator?.moduleID != module.details.id {
            activeModuleCoordinator = module.makeCoordinator(
                context: ModuleContext(dependencies: dependencies, workflowActions: self)
            )
            route = .moduleWorkflow
        }
        activeModuleCoordinator?.goToNextStep(for: project, startAtLastReviewed: startAtLastReviewed)
        workflowRevision += 1
    }

    func goToPreviousStep(for project: Project) {
        project.lastOpenedAt = .now
        goBack()
    }

    func openReadOnlyProject(_ project: Project) {
        project.lastOpenedAt = .now

        guard let module = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID)) else {
            route = .projectSelection
            return
        }

        let coordinator = module.makeCoordinator(
            context: ModuleContext(dependencies: dependencies, workflowActions: self)
        )
        coordinator.openReadOnlyProject(project)
        activeModuleCoordinator = coordinator
        workflowRevision += 1
        route = .moduleWorkflow
    }

    func continueProject(_ project: Project) {
        project.lastOpenedAt = .now

        guard let module = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID)) else {
            openReadOnlyProject(project)
            return
        }

        let coordinator = module.makeCoordinator(
            context: ModuleContext(dependencies: dependencies, workflowActions: self)
        )
        coordinator.resume(project: project)
        activeModuleCoordinator = coordinator
        workflowRevision += 1
        route = .moduleWorkflow
    }
}
