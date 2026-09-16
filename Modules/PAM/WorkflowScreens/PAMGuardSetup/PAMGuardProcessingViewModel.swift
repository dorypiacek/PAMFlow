//
//  PAMGuardProcessingViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import UI
import Core
import Observation
import SwiftData

/// Defines state and commands for importing PAMGuard detection output.
@MainActor
protocol PAMGuardProcessingViewModelType: AnyObject {
    /// Primary status text displayed while detections are imported.
    var message: String { get }
    /// Normalized import progress, or `nil` while progress is indeterminate.
    var progress: Double? { get }
    /// User-facing error if PAMGuard output cannot be processed.
    var errorMessage: String? { get }
    /// Prevents the processing task from starting more than once per view lifetime.
    var hasStarted: Bool { get }

    /// Starts import when it has not already been started.
    func startIfNeeded(modelContext: ModelContext, workflowActions: WorkflowActionHandling)
    /// Imports PAMGuard detections, stores the updated scan summary, and advances the workflow.
    func start(project: Project, modelContext: ModelContext, workflowActions: WorkflowActionHandling)
    /// Fetches the project associated with this processing screen.
    func fetchProject(modelContext: ModelContext) -> Project?
}

/// View model for the audio module's detection-import processing screen.
@Observable
@MainActor
final class PAMGuardProcessingViewModel: PAMGuardProcessingViewModelType {
    /// Primary status text displayed while detections are imported.
    var message = PAMStrings.Processing.starting
    /// Normalized import progress, or `nil` while progress is indeterminate.
    var progress: Double?
    /// User-facing error if PAMGuard output cannot be processed.
    var errorMessage: String?
    /// Prevents the processing task from starting more than once per view lifetime.
    var hasStarted = false

    /// Identifier of the project being processed.
    private let projectID: UUID
    /// Service used to load the summary generated before PAMGuard setup.
    private let projectScanService: ProjectScanServicing
    /// Service used to import PAMGuard detections into the project summary.
    private let processingService: PAMGuardDetectionProcessingServicing

    /// Creates processing state using injectable scan and PAMGuard processing services.
    init(
        projectID: UUID,
        projectScanService: ProjectScanServicing,
        processingService: PAMGuardDetectionProcessingServicing
    ) {
        self.projectID = projectID
        self.projectScanService = projectScanService
        self.processingService = processingService
    }

    func startIfNeeded(modelContext: ModelContext, workflowActions: WorkflowActionHandling) {
        guard !hasStarted, let project = fetchProject(modelContext: modelContext) else { return }
        hasStarted = true
        start(project: project, modelContext: modelContext, workflowActions: workflowActions)
    }

    func start(project: Project, modelContext: ModelContext, workflowActions: WorkflowActionHandling) {
        errorMessage = nil
        progress = nil
        message = PAMStrings.Processing.starting

        Task {
            do {
                let originalSummary = try projectScanService.loadSummary(for: project)
                let summary = try await processingService.process(project: project, originalSummary: originalSummary) { update in
                    Task { @MainActor in
                        self.message = update.message
                        self.progress = update.fractionCompleted
                    }
                }

                project.workflowStatus = .processingRunImported
                project.lastOpenedAt = .now
                try project.storeScanSummary(summary)
                try modelContext.save()
                workflowActions.goToNextStep(for: project)
            } catch {
                errorMessage = error.localizedDescription
                message = PAMStrings.Processing.failed
            }
        }
    }

    func fetchProject(modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
