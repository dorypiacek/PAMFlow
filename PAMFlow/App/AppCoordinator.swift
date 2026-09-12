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
    func openModuleScreen(_ route: ModuleScreenRoute)
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
final class AppCoordinator: AppCoordinating {
    var userProfile: UserProfile?
    var route: AppRoute
    var selectedTheme: AppTheme
    var settingsErrorMessage: String?
    #if DEBUG
    var simulateSharkTrackProcessing: Bool
    #endif

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
        #if DEBUG
        self.simulateSharkTrackProcessing = UserDefaults.standard.bool(
            forKey: SharkTrackService.simulateSharkTrackUserDefaultsKey
        )
        #endif
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

    #if DEBUG
    func setSharkTrackSimulation(_ isEnabled: Bool) {
        simulateSharkTrackProcessing = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: SharkTrackService.simulateSharkTrackUserDefaultsKey)
    }
    #endif

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
        route = .moduleFlow(moduleID: moduleID)
    }

    func openModuleScreen(_ screenRoute: ModuleScreenRoute) {
        route = .moduleScreen(screenRoute)
    }

    func openProjectSelection() {
        route = .projectSelection
    }

    func goHome() {
        route = userProfile == nil ? .welcome : .projectSelection
    }

    func goBack() {
        switch route {
        case .welcome, .projectSelection:
            break
        case .dataTypeSelection:
            route = .projectSelection
        case .moduleFlow:
            route = .dataTypeSelection
        case .moduleScreen(let screen):
            guard let module = moduleCatalog.module(for: screen.moduleID) else {
                route = .projectSelection
                return
            }
            route = module.makeCoordinator(
                context: ModuleContext(dependencies: dependencies, appCoordinator: self)
            )
            .previousRoute(for: screen)
        }
    }

    func goToNextStep(for project: Project, startAtLastReviewed: Bool = false) {
        project.lastOpenedAt = .now

        guard let module = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID)) else {
            openReadOnlyProject(project)
            return
        }

        module.makeCoordinator(
            context: ModuleContext(dependencies: dependencies, appCoordinator: self)
        )
        .openNextStep(for: project, from: route, startAtLastReviewed: startAtLastReviewed)
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

        module.makeCoordinator(
            context: ModuleContext(dependencies: dependencies, appCoordinator: self)
        )
        .openReadOnlyProject(project)
    }

    func continueProject(_ project: Project) {
        project.lastOpenedAt = .now

        guard let module = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID)) else {
            openReadOnlyProject(project)
            return
        }

        module.makeCoordinator(
            context: ModuleContext(dependencies: dependencies, appCoordinator: self)
        )
        .openLatestProject(project)
    }
}
