//
//  ManualAuditOverviewViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/08/2026.
//

import Foundation
import Core
import SwiftData

/// Defines state and commands for the manual-audit overview screen.
@MainActor
protocol ManualAuditOverviewViewModelType: AnyObject {
    /// Loaded project associated with the overview.
    var project: Project? { get }
    /// Loaded scan summary used to build overview metrics.
    var summary: ProjectScanSummary? { get }
    /// User-facing load or persistence error.
    var errorMessage: String? { get }

    /// Loads the project and scan summary from persistence.
    func load(modelContext: ModelContext)
    /// Builds the deterministic presentation model for current persisted audit decisions.
    func overviewModel(modelContext: ModelContext) -> ManualAuditOverviewPresentation?
    /// Applies the primary overview action and delegates navigation to the coordinator.
    func completePrimaryAction(
        modelContext: ModelContext,
        overview: ManualAuditOverviewPresentation,
        coordinator: AppCoordinating
    ) throws
}

/// View model for manual-audit overview state and workflow transitions.
@MainActor
@Observable
open class ManualAuditOverviewViewModel: ManualAuditOverviewViewModelType {
    /// Identifier of the project represented by this overview.
    private let projectID: UUID
    /// Service used to load the scan summary for overview metrics.
    private let projectScanService: ProjectScanServicing

    /// Loaded project associated with the overview.
    private(set) var project: Project?
    /// Loaded scan summary used to build overview metrics.
    private(set) var summary: ProjectScanSummary?
    /// User-facing load or persistence error.
    private(set) var errorMessage: String?

    /// Creates a ViewModel for a specific project overview.
    public init(projectID: UUID, projectScanService: ProjectScanServicing) {
        self.projectID = projectID
        self.projectScanService = projectScanService
    }

    /// Loads the project and its scan summary from app persistence.
    open func load(modelContext: ModelContext) {
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
    public func overviewModel(modelContext: ModelContext) -> ManualAuditOverviewPresentation? {
        guard let project, let summary else { return nil }
        return ManualAuditOverviewPresentation(
            project: project,
            summary: summary,
            decisions: auditDecisions(for: project, modelContext: modelContext),
            configuration: overviewConfiguration(project: project, summary: summary)
        )
    }

    open func overviewConfiguration(
        project: Project,
        summary: ProjectScanSummary
    ) -> ManualAuditOverviewPresentation.Configuration {
        .generic
    }

    /// Applies the primary overview action and delegates navigation to the coordinator.
    open func completePrimaryAction(
        modelContext: ModelContext,
        overview: ManualAuditOverviewPresentation,
        coordinator: AppCoordinating
    ) throws {
        let project = overview.project
        let opensCompletion = overview.opensCompletionFromPrimaryAction

        if !overview.isComplete {
            project.workflowStatus = inProgressStatus(for: overview)
            project.lastOpenedAt = .now
            try modelContext.save()
            coordinator.goToNextStep(for: project, startAtLastReviewed: true)
            return
        }

        project.workflowStatus = opensCompletion
            ? .completed
            : .created
        project.lastOpenedAt = .now
        try modelContext.save()

        coordinator.goToNextStep(for: project)
    }

    open func inProgressStatus(for overview: ManualAuditOverviewPresentation) -> ProjectWorkflowStatus {
        .inProgress
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
