//
//  ProjectCompletionViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import Observation
import SwiftData

/// Defines the completion screen state, export commands, and project finalization actions.
@MainActor
protocol ProjectCompletionViewModelType: AnyObject {
    /// Loaded scan summary used to render completion metrics and exports.
    var summary: ProjectScanSummary? { get }
    /// Ordered export field identifiers selected by the user, or `nil` for saved/default fields.
    var selectedFieldIDs: [String]? { get set }
    /// Controls the export-field customization sheet.
    var isCustomisingFields: Bool { get set }
    /// User-facing failure text for loading, export, deletion, or completion.
    var errorMessage: String? { get set }
    /// User-facing confirmation after a successful export.
    var successMessage: String? { get }

    /// Fetches the project associated with this screen from SwiftData.
    func fetchProject(modelContext: ModelContext) -> Project?
    /// Loads the persisted scan summary for the current project.
    func loadSummary(modelContext: ModelContext)
    /// Returns all manual-audit decisions for the project.
    func auditDecisions(for project: Project, modelContext: ModelContext) -> [ManualAuditDecision]
    /// Resolves export fields from the current user selection, saved defaults, or module defaults.
    func activeFields(for module: WorkflowModule) -> [ProjectExportField]
    /// Resolves ordered export field identifiers for the supplied module.
    func activeFieldIDs(for module: WorkflowModule) -> [String]
    /// Persists the user's export-field selection for the supplied module.
    func saveFieldIDs(_ fieldIDs: [String], for module: WorkflowModule)
    /// Writes the module-appropriate export package and marks the project complete on success.
    func export(project: Project, decisions: [ManualAuditDecision], fields: [ProjectExportField], modelContext: ModelContext, appCoordinator: AppCoordinating)
    /// Marks the project complete, removes temporary artifacts, and returns to project selection.
    func complete(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating) -> Bool
    /// Deletes a project whose folder can no longer be loaded from the completion screen.
    func deleteUnavailableProject(_ project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating)
    /// Returns the display name registered for the project's module.
    func moduleName(for project: Project, appCoordinator: AppCoordinating) -> String
    /// Returns the stored completer name or the current reviewer fallback.
    func processedBy(for project: Project, appCoordinator: AppCoordinating) -> String
    /// Formats the minimum and maximum media duration from a scan summary.
    func durationRange(_ summary: ProjectScanSummary) -> String
}

/// View model for project completion, reporting, export configuration, and cleanup.
@Observable
@MainActor
final class ProjectCompletionViewModel: ProjectCompletionViewModelType {
    /// Loaded scan summary used to render completion metrics and exports.
    var summary: ProjectScanSummary?
    /// Ordered export field identifiers selected by the user, or `nil` for saved/default fields.
    var selectedFieldIDs: [String]?
    /// Controls the export-field customization sheet.
    var isCustomisingFields = false
    /// User-facing failure text for loading, export, deletion, or completion.
    var errorMessage: String?
    /// User-facing confirmation after a successful export.
    var successMessage: String?

    /// Identifier of the project being completed.
    private let projectID: UUID
    /// Service used to load the scan summary that backs metrics and exports.
    private let projectScanService: ProjectScanServicing

    /// Creates completion state for a persisted project and scan-summary service.
    init(projectID: UUID, projectScanService: ProjectScanServicing) {
        self.projectID = projectID
        self.projectScanService = projectScanService
    }

    func fetchProject(modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func loadSummary(modelContext: ModelContext) {
        guard let project = fetchProject(modelContext: modelContext) else {
            errorMessage = Strings.Common.projectNotFound
            return
        }

        do {
            summary = try projectScanService.loadSummary(for: project)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func auditDecisions(for project: Project, modelContext: ModelContext) -> [ManualAuditDecision] {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func activeFields(for module: WorkflowModule) -> [ProjectExportField] {
        activeFieldIDs(for: module).compactMap { ProjectExportField.field(id: $0, module: module) }
    }

    func activeFieldIDs(for module: WorkflowModule) -> [String] {
        if let selectedFieldIDs {
            return selectedFieldIDs
        }
        if let saved = UserDefaults.standard.stringArray(forKey: exportFieldDefaultsKey(module)) {
            return ProjectExportField.includingRequiredDefaults(saved, for: module)
        }
        return ProjectExportField.defaults(for: module).map(\.id)
    }

    func saveFieldIDs(_ fieldIDs: [String], for module: WorkflowModule) {
        selectedFieldIDs = fieldIDs
        UserDefaults.standard.set(fieldIDs, forKey: exportFieldDefaultsKey(module))
    }

    func export(
        project: Project,
        decisions: [ManualAuditDecision],
        fields: [ProjectExportField],
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    ) {
        guard let summary else { return }
        let module = WorkflowModule.module(for: project.moduleID)
        if module == .pamAudio {
            exportPAMPackage(project: project, summary: summary, decisions: decisions, modelContext: modelContext, appCoordinator: appCoordinator)
        } else {
            exportCSV(project: project, summary: summary, decisions: decisions, fields: fields, modelContext: modelContext, appCoordinator: appCoordinator)
        }
    }

    @discardableResult
    func complete(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating) -> Bool {
        guard let summary else { return false }
        if completeProject(project, summary: summary, modelContext: modelContext, appCoordinator: appCoordinator) {
            appCoordinator.openProjectSelection()
            return true
        }
        return false
    }

    func deleteUnavailableProject(_ project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating) {
        do {
            try appCoordinator.dependencies.projectFileService.deleteProjectFolder(for: project)
            deleteAuditDecisions(for: project, modelContext: modelContext)
            modelContext.delete(project)
            try modelContext.save()
            appCoordinator.openProjectSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moduleName(for project: Project, appCoordinator: AppCoordinating) -> String {
        appCoordinator.moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))?.details.name ?? project.moduleID
    }

    func processedBy(for project: Project, appCoordinator: AppCoordinating) -> String {
        guard let completedBy = project.completedBy?.trimmed, !completedBy.isEmpty else {
            return currentReviewerName(appCoordinator: appCoordinator)
        }

        return completedBy
    }

    func durationRange(_ summary: ProjectScanSummary) -> String {
        guard let min = summary.durationMinSeconds, let max = summary.durationMaxSeconds else {
            return Strings.Common.unknown
        }

        return "\(formatDuration(min)) - \(formatDuration(max))"
    }

    private func exportCSV(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        fields: [ProjectExportField],
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    ) {
        guard let url = appCoordinator.dependencies.fileSelectionService.selectSaveDestination(
            defaultName: "\(project.name)_detections.csv",
            canCreateDirectories: true
        ) else { return }

        do {
            let report = ProjectExportReport(
                project: project,
                summary: summary,
                decisions: decisions,
                fields: fields,
                separator: ",",
                processedBy: processedBy(for: project, appCoordinator: appCoordinator)
            )
            try report.string.write(to: url, atomically: true, encoding: .utf8)
            saveExportSuccess(url: url, project: project, summary: summary, modelContext: modelContext, appCoordinator: appCoordinator)
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    private func exportPAMPackage(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    ) {
        guard let url = appCoordinator.dependencies.fileSelectionService.selectSaveDestination(
            defaultName: "\(project.name)_detections",
            canCreateDirectories: true
        ) else { return }

        do {
            let exporter = PAMDetectionPackageExporter(
                project: project,
                summary: summary,
                decisions: decisions,
                processedBy: processedBy(for: project, appCoordinator: appCoordinator)
            )
            try exporter.writePackage(to: url)
            saveExportSuccess(url: url, project: project, summary: summary, modelContext: modelContext, appCoordinator: appCoordinator)
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    private func saveExportSuccess(
        url: URL,
        project: Project,
        summary: ProjectScanSummary,
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    ) {
        if completeProject(project, summary: summary, modelContext: modelContext, appCoordinator: appCoordinator) {
            successMessage = String(format: Strings.ProjectCompletion.exportSuccessFormat, url.lastPathComponent)
            errorMessage = nil
        }
    }

    @discardableResult
    private func completeProject(
        _ project: Project,
        summary: ProjectScanSummary,
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    ) -> Bool {
        if project.completedBy?.trimmed.isEmpty ?? true {
            project.completedBy = currentReviewerName(appCoordinator: appCoordinator)
        }
        project.workflowStatus = .completed
        project.lastOpenedAt = .now
        do {
            if let rootFolderURL = project.rootFolderURL {
                do {
                    try ProjectScanService.writeSummary(summary, projectRootURL: rootFolderURL)
                } catch {
                    AppLog.info("Project completion skipped internal scan summary refresh: \(error.localizedDescription)")
                }
            }
            try project.storeScanSummary(summary)
            try modelContext.save()
            try appCoordinator.dependencies.projectFileService.removeTemporaryArtifacts(for: project)
            return true
        } catch {
            errorMessage = Strings.ProjectCompletion.completionSaveFailed
            return false
        }
    }

    private func deleteAuditDecisions(for project: Project, modelContext: ModelContext) {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        guard let decisions = try? modelContext.fetch(descriptor) else { return }

        for decision in decisions {
            modelContext.delete(decision)
        }
    }

    private func exportFieldDefaultsKey(_ module: WorkflowModule) -> String {
        "pamflow.export.fields.\(module.id)"
    }

    private func currentReviewerName(appCoordinator: AppCoordinating) -> String {
        appCoordinator.userProfile?.name.trimmed ?? Strings.Common.unknownUser
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
