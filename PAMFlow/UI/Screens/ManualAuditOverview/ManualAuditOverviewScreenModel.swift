//
//  ManualAuditOverviewScreenModel.swift
//  PAMFlow
//
//  Created by Codex on 12/08/2026.
//

import Foundation
import SwiftData

/// Loads and owns screen state for manual audit overview while keeping SwiftUI rendering stateless.
@MainActor
@Observable
final class ManualAuditOverviewScreenModel {
    private let projectID: UUID
    private let projectScanService: ProjectScanServicing

    private(set) var project: Project?
    private(set) var summary: ProjectScanSummary?
    private(set) var errorMessage: String?

    /// Creates a screen model for a specific project overview.
    init(projectID: UUID, projectScanService: ProjectScanServicing) {
        self.projectID = projectID
        self.projectScanService = projectScanService
    }

    /// Loads the project and its scan summary from app persistence.
    func load(modelContext: ModelContext) {
        guard let project = fetchProject(modelContext: modelContext) else {
            self.project = nil
            summary = nil
            errorMessage = Strings.Common.projectNotFound
            return
        }

        do {
            self.project = project
            summary = try projectScanService.loadSummary(for: project)
            errorMessage = nil
        } catch {
            self.project = project
            summary = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Builds the deterministic presentation model for current persisted audit decisions.
    func overviewModel(modelContext: ModelContext) -> ManualAuditOverviewModel? {
        guard let project, let summary else { return nil }
        return ManualAuditOverviewModel(
            project: project,
            summary: summary,
            decisions: auditDecisions(for: project, modelContext: modelContext)
        )
    }

    /// Applies the primary overview action and delegates navigation to the coordinator.
    func completePrimaryAction(
        modelContext: ModelContext,
        overview: ManualAuditOverviewModel,
        coordinator: AppCoordinating
    ) throws {
        let project = overview.project
        let opensCompletion = overview.opensCompletionFromPrimaryAction
        project.workflowStatus = opensCompletion
            ? .completed
            : .processingProjectCreated
        project.lastOpenedAt = .now
        try modelContext.save()

        if opensCompletion {
            coordinator.openProjectCompletion(project)
            return
        }

        if overview.module.usesPAMGuard {
            coordinator.openPAMGuardSetup(project)
            return
        }

        coordinator.openProjectCompletion(project)
    }

    private func fetchProject(modelContext: ModelContext) -> Project? {
        let projectID = projectID
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
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
