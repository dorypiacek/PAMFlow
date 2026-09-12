//
//  PAMGuardWaitingViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import Observation
import SwiftData

/// Defines state and commands for the screen that waits for a user-run PAMGuard pass.
@MainActor
protocol PAMGuardWaitingViewModelType: AnyObject {
    /// Controls presentation of PAMGuard run instructions.
    var showsPAMGuardHelp: Bool { get set }

    /// Fetches the project associated with this waiting screen.
    func fetchProject(modelContext: ModelContext) -> Project?
    /// Marks the manual PAMGuard run as complete and advances to import processing.
    func confirmRunFinished(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating)
    /// Builds an action that reveals the PAMGuard project folder when available.
    func pamguardFolderRevealAction(modelContext: ModelContext) -> (() -> Void)?
}

/// View model for the PAMGuard waiting step between template generation and import.
@Observable
@MainActor
final class PAMGuardWaitingViewModel: PAMGuardWaitingViewModelType {
    /// Controls presentation of PAMGuard run instructions.
    var showsPAMGuardHelp = false

    /// Identifier of the project waiting for a PAMGuard run.
    private let projectID: UUID

    /// Creates waiting state for a persisted PAM project.
    init(projectID: UUID) {
        self.projectID = projectID
    }

    /// Persists the workflow transition after the user confirms the PAMGuard run is finished.
    func confirmRunFinished(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating) {
        project.workflowStatus = .processingRunImported
        project.lastOpenedAt = .now
        try? modelContext.save()
        appCoordinator.goToNextStep(for: project)
    }

    /// Returns a Finder reveal action for the generated PAMGuard folder.
    func pamguardFolderRevealAction(modelContext: ModelContext) -> (() -> Void)? {
        guard let project = fetchProject(modelContext: modelContext),
              let projectRootURL = project.rootFolderURL else {
            return nil
        }

        return {
            let accessed = projectRootURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    projectRootURL.stopAccessingSecurityScopedResource()
                }
            }

            FileSelectionService.revealInFinder(projectRootURL.appendingPathComponent(PAMProjectFileNames.pamguardDirectory))
        }
    }

    /// Loads the project backing the waiting screen.
    func fetchProject(modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
