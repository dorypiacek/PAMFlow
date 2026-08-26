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
    var canGoBack: Bool { get }
    var canGoHome: Bool { get }

    @discardableResult
    func saveUserName(_ name: String) -> Bool
    func signOut()
    func selectTheme(_ theme: AppTheme)
    func openDataTypeSelection()
    func openProjectSetup(module: WorkflowModule)
    func openProjectSelection()
    func goHome()
    func goBack()
    func scanProject(_ project: Project)
    func openNewProjectOverview(_ project: Project)
    func openSharkTrackProcessing(_ project: Project)
    func openManualAudit(_ project: Project, startAtLastReviewed: Bool)
    func openManualAuditOverview(_ project: Project)
    func openPAMGuardSetup(_ project: Project)
    func openPAMGuardWaiting(_ project: Project)
    func openPAMGuardProcessing(_ project: Project)
    func openProjectCompletion(_ project: Project)
    func continueProject(_ project: Project)
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

    init(
        userProfileStore: UserProfileStoring,
        appThemeStore: AppThemeStoring,
        dependencies: Dependencies
    ) {
        self.userProfileStore = userProfileStore
        self.appThemeStore = appThemeStore
        self.dependencies = dependencies
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

    func openProjectSetup(module: WorkflowModule) {
        route = .projectSetup(module: module)
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
        case .projectSetup:
            route = .dataTypeSelection
        case .scanProject:
            route = .dataTypeSelection
        case .newProjectOverview(let projectID):
            route = .scanProject(projectID: projectID)
        case .sharkTrackProcessing(let projectID):
            route = .newProjectOverview(projectID: projectID)
        case .manualAudit(let projectID, _):
            route = .newProjectOverview(projectID: projectID)
        case .manualAuditOverview(let projectID):
            route = .manualAudit(projectID: projectID, startAtLastReviewed: true)
        case .pamguardSetup(let projectID):
            route = .manualAuditOverview(projectID: projectID)
        case .pamguardWaiting(let projectID):
            route = .pamguardSetup(projectID: projectID)
        case .pamguardProcessing(let projectID):
            route = .pamguardWaiting(projectID: projectID)
        case .projectCompletion(let projectID):
            route = .manualAuditOverview(projectID: projectID)
        }
    }

    func scanProject(_ project: Project) {
        project.lastOpenedAt = .now
        route = .scanProject(projectID: project.id)
    }

    func openNewProjectOverview(_ project: Project) {
        project.lastOpenedAt = .now
        route = .newProjectOverview(projectID: project.id)
    }

    func openSharkTrackProcessing(_ project: Project) {
        project.lastOpenedAt = .now
        route = .sharkTrackProcessing(projectID: project.id)
    }

    func openManualAudit(_ project: Project, startAtLastReviewed: Bool = false) {
        project.lastOpenedAt = .now
        route = .manualAudit(projectID: project.id, startAtLastReviewed: startAtLastReviewed)
    }

    func openManualAuditOverview(_ project: Project) {
        project.lastOpenedAt = .now
        route = .manualAuditOverview(projectID: project.id)
    }

    func openPAMGuardSetup(_ project: Project) {
        project.lastOpenedAt = .now
        route = .pamguardSetup(projectID: project.id)
    }

    func openPAMGuardWaiting(_ project: Project) {
        project.lastOpenedAt = .now
        route = .pamguardWaiting(projectID: project.id)
    }

    func openPAMGuardProcessing(_ project: Project) {
        project.lastOpenedAt = .now
        route = .pamguardProcessing(projectID: project.id)
    }

    func openProjectCompletion(_ project: Project) {
        project.lastOpenedAt = .now
        route = .projectCompletion(projectID: project.id)
    }

    func continueProject(_ project: Project) {
        project.lastOpenedAt = .now
        let module = WorkflowModule.module(for: project.moduleID)

        switch project.workflowStatus {
        case .created, .scanInProgress:
            scanProject(project)
        case .scanCompleted:
            if module.requiresSharkTrack {
                openSharkTrackProcessing(project)
            } else {
                openNewProjectOverview(project)
            }
        case .manualAuditInProgress:
            openManualAudit(project)
        case .manualAuditCompleted:
            openManualAuditOverview(project)
        case .pamguardSetupReady:
            if module.usesPAMGuard {
                openPAMGuardSetup(project)
            } else {
                openManualAuditOverview(project)
            }
        case .processingProjectCreated:
            if module.requiresSharkTrack {
                if hasReviewFrames(project) {
                    openManualAudit(project)
                } else {
                    openManualAuditOverview(project)
                }
            } else {
                openPAMGuardWaiting(project)
            }
        case .processingRunImported:
            if module.usesPAMGuard {
                openManualAuditOverview(project)
            } else {
                openNewProjectOverview(project)
            }
        case .runOverviewCompleted:
            if module.usesPAMGuard {
                openManualAudit(project)
            } else {
                openNewProjectOverview(project)
            }
        case .detectionReviewInProgress:
            if module.usesPAMGuard {
                openManualAudit(project, startAtLastReviewed: true)
            } else {
                openNewProjectOverview(project)
            }
        case .completed:
            openProjectCompletion(project)
        }
    }

    private func hasReviewFrames(_ project: Project) -> Bool {
        (try? dependencies.projectScanService.loadSummary(for: project).fileCount) ?? 0 > 0
    }
}
