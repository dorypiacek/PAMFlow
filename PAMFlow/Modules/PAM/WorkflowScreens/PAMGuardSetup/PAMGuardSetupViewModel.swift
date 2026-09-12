//
//  PAMGuardSetupViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import Observation
import SwiftData

/// Defines state and commands for preparing the generated PAMGuard project package.
@MainActor
protocol PAMGuardSetupViewModelType: AnyObject {
    /// Selected detection target used to create the PAMGuard template.
    var selectedTarget: PAMGuardPreparationService.DetectionTarget? { get set }
    /// Result of the latest successful PAMGuard preparation.
    var result: PAMGuardPreparationService.Result? { get }
    /// User-facing preparation or restoration error.
    var errorMessage: String? { get }
    /// Indicates whether template preparation is running.
    var isPreparing: Bool { get }
    /// Controls presentation of PAMGuard run instructions.
    var showsPAMGuardHelp: Bool { get set }

    /// Fetches the project associated with this setup screen.
    func fetchProject(modelContext: ModelContext) -> Project?
    /// Creates or updates the PAMGuard folder and template for the selected detection target.
    func prepare(project: Project, modelContext: ModelContext)
    /// Marks setup complete and opens the module's next workflow step.
    func continueWorkflow(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating)
    /// Reveals the generated PAMGuard template in Finder.
    func revealTemplateInFinder(_ templateURL: URL, project: Project)
    /// Builds an action that reveals the generated PAMGuard folder when preparation has succeeded.
    func pamguardFolderRevealAction(modelContext: ModelContext) -> (() -> Void)?
    /// Restores preparation state from disk so returning users can continue without regenerating files.
    func restorePreparedResultIfNeeded(modelContext: ModelContext)
}

/// View model for the PAM module's PAMGuard setup step.
@Observable
@MainActor
final class PAMGuardSetupViewModel: PAMGuardSetupViewModelType {
    /// Selected detection target used to create the PAMGuard template.
    var selectedTarget: PAMGuardPreparationService.DetectionTarget?
    /// Result of the latest successful PAMGuard preparation.
    var result: PAMGuardPreparationService.Result?
    /// User-facing preparation or restoration error.
    var errorMessage: String?
    /// Indicates whether template preparation is running.
    var isPreparing = false
    /// Controls presentation of PAMGuard run instructions.
    var showsPAMGuardHelp = false

    /// Identifier of the project being prepared for PAMGuard.
    private let projectID: UUID
    /// Service used to load the scan summary required for PAMGuard preparation.
    private let projectScanService: ProjectScanServicing
    /// Service that creates PAMGuard folders, input links, and template files.
    private let preparationService: PAMGuardPreparationServicing

    /// Creates setup state using injectable scan and preparation services.
    init(
        projectID: UUID,
        projectScanService: ProjectScanServicing,
        preparationService: PAMGuardPreparationServicing
    ) {
        self.projectID = projectID
        self.projectScanService = projectScanService
        self.preparationService = preparationService
    }

    /// Prepares the external PAMGuard project package for the selected target.
    func prepare(project: Project, modelContext: ModelContext) {
        guard let target = selectedTarget else { return }
        isPreparing = true
        errorMessage = nil
        result = nil

        do {
            let summary = try projectScanService.loadSummary(for: project)
            let preparedResult = try preparationService.prepare(
                project: project,
                scanSummary: summary,
                decisions: auditDecisions(for: project, modelContext: modelContext),
                target: target
            )
            project.workflowStatus = .pamguardSetupReady
            project.lastOpenedAt = .now
            try modelContext.save()
            result = preparedResult
        } catch {
            errorMessage = error.localizedDescription
        }

        isPreparing = false
    }

    /// Persists the workflow transition to the waiting/import phase.
    func continueWorkflow(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating) {
        project.workflowStatus = .processingProjectCreated
        project.lastOpenedAt = .now
        try? modelContext.save()
        appCoordinator.goToNextStep(for: project)
    }

    /// Reveals a generated PAMGuard template while respecting project folder security scope.
    func revealTemplateInFinder(_ templateURL: URL, project: Project) {
        let projectRootURL = project.rootFolderURL
        let accessed = projectRootURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessed {
                projectRootURL?.stopAccessingSecurityScopedResource()
            }
        }

        FileSelectionService.revealInFinder(templateURL)
    }

    /// Returns a Finder reveal closure for the generated template when one can be resolved.
    func pamguardFolderRevealAction(modelContext: ModelContext) -> (() -> Void)? {
        guard let project = fetchProject(modelContext: modelContext),
              let preparedResult = result ?? restoredPreparedResult(for: project) else {
            return nil
        }

        return {
            let projectRootURL = project.rootFolderURL
            let accessed = projectRootURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if accessed {
                    projectRootURL?.stopAccessingSecurityScopedResource()
                }
            }

            FileSelectionService.revealInFinder(preparedResult.templateURL)
        }
    }

    /// Rehydrates a previous preparation result by inspecting the generated PAMGuard folder.
    func restorePreparedResultIfNeeded(modelContext: ModelContext) {
        guard result == nil,
              let project = fetchProject(modelContext: modelContext),
              let restoredResult = restoredPreparedResult(for: project) else {
            return
        }

        result = restoredResult
    }

    /// Loads the project backing this setup screen.
    func fetchProject(modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func restoredPreparedResult(for project: Project) -> PAMGuardPreparationService.Result? {
        guard let projectRootURL = project.rootFolderURL else {
            return nil
        }

        let accessed = projectRootURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                projectRootURL.stopAccessingSecurityScopedResource()
            }
        }

        let pamguardURL = projectRootURL.appendingPathComponent(PAMProjectFileNames.pamguardDirectory, isDirectory: true)
        let inputURL = pamguardURL.appendingPathComponent("input", isDirectory: true)
        guard let templateURL = firstTemplateURL(in: pamguardURL) else {
            return nil
        }

        let linkedInputCount = (try? FileManager.default.contentsOfDirectory(
            at: inputURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).count) ?? 0

        return PAMGuardPreparationService.Result(
            templateURL: templateURL,
            linkedInputCount: linkedInputCount
        )
    }

    private func firstTemplateURL(in pamguardURL: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: pamguardURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return files
            .filter { $0.pathExtension.localizedCaseInsensitiveCompare("psfx") == .orderedSame }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private func auditDecisions(for project: Project, modelContext: ModelContext) -> [ManualAuditDecision] {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
