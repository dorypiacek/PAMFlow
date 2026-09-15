//
//  AppCoordinating.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Core
import SwiftUI

/// Host-app actions and shared state that package-owned views may request.
///
/// The UI package depends on this protocol instead of the concrete app
/// coordinator so shared screens can be compiled and tested without the app
/// target. The app target provides the implementation and injects it through
/// SwiftUI environment values.
@MainActor
public protocol AppCoordinating: AnyObject {
    /// The signed-in user shown by shared chrome and settings screens.
    var userProfile: UserProfile? { get }
    /// The active visual theme selected for the app shell.
    var selectedTheme: AppTheme { get set }
    /// Shared services available to app screens and feature modules.
    var dependencies: SharedAppDependencies { get }
    /// The included feature-module catalog for the current build.
    var moduleCatalog: ModuleCatalog { get }
    /// Whether the current app route can navigate backward.
    var canGoBack: Bool { get }
    /// Whether the current app route can exit to the project list.
    var canGoHome: Bool { get }

    /// Persists the user's display name and opens the main app experience.
    @discardableResult
    func saveUserName(_ name: String) -> Bool
    /// Clears the current user profile and returns to onboarding.
    func signOut()
    /// Persists and applies a new app theme.
    func selectTheme(_ theme: AppTheme)
    /// Opens the module-selection screen.
    func openDataTypeSelection()
    /// Starts a new workflow in the selected module.
    func openModule(moduleID: ModuleID)
    /// Returns to the project library.
    func openProjectSelection()
    /// Returns to the host app from the current screen.
    func goHome()
    /// Navigates back in the active host or module route.
    func goBack()
    /// Asks the owning module to advance the project workflow.
    func goToNextStep(for project: Project, startAtLastReviewed: Bool)
    /// Asks the owning module to move back from the current workflow step.
    func goToPreviousStep(for project: Project)
    /// Opens a saved project without requiring the original project folder.
    func openReadOnlyProject(_ project: Project)
    /// Resumes a saved project through its owning module.
    func continueProject(_ project: Project)
}

public extension AppCoordinating {
    /// Asks the owning module to advance the project workflow from the current step.
    func goToNextStep(for project: Project) {
        goToNextStep(for: project, startAtLastReviewed: false)
    }
}

private struct AppCoordinatorEnvironmentKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (any AppCoordinating)? = nil
}

public extension EnvironmentValues {
    /// Host coordinator injected by the app target for shared UI screens.
    var appCoordinator: (any AppCoordinating)? {
        get { self[AppCoordinatorEnvironmentKey.self] }
        set { self[AppCoordinatorEnvironmentKey.self] = newValue }
    }
}
