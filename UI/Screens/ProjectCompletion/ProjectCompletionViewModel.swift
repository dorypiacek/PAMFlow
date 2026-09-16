//
//  ProjectCompletionViewModel.swift
//  PAMFlow
//
//  Created by Dory on 14/09/2026.
//

import Core
import Foundation
import Observation
import SwiftData

/// Module-provided copy and actions for the shared project-completion screen.
public struct ProjectCompletionConfiguration: Sendable {
    public let title: String
    public let subtitle: String
    public let overviewTitle: String
    public let projectTitle: String
    public let processedByTitle: String
    public let reviewedFilesTitle: String
    public let validDecisionsTitle: String
    public let unsureDecisionsTitle: String
    public let invalidDecisionsTitle: String
    public let completeButtonTitle: String
    public let backToProjectsButtonTitle: String
    public let exportButtonTitle: String?

    public init(
        title: String,
        subtitle: String,
        overviewTitle: String,
        projectTitle: String,
        processedByTitle: String,
        reviewedFilesTitle: String,
        validDecisionsTitle: String,
        unsureDecisionsTitle: String,
        invalidDecisionsTitle: String,
        completeButtonTitle: String,
        backToProjectsButtonTitle: String,
        exportButtonTitle: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.overviewTitle = overviewTitle
        self.projectTitle = projectTitle
        self.processedByTitle = processedByTitle
        self.reviewedFilesTitle = reviewedFilesTitle
        self.validDecisionsTitle = validDecisionsTitle
        self.unsureDecisionsTitle = unsureDecisionsTitle
        self.invalidDecisionsTitle = invalidDecisionsTitle
        self.completeButtonTitle = completeButtonTitle
        self.backToProjectsButtonTitle = backToProjectsButtonTitle
        self.exportButtonTitle = exportButtonTitle
    }
}

/// One value rendered in the shared completion overview grid.
public struct ProjectCompletionMetric: Identifiable, Equatable {
    public let title: String
    public let value: String

    public var id: String { "\(title)-\(value)" }

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

/// Module-owned export column rendered by the shared completion screen.
public struct ProjectCompletionExportField: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let isRequired: Bool

    public init(id: String, title: String, isRequired: Bool = false) {
        self.id = id
        self.title = title
        self.isRequired = isRequired
    }
}

/// Contract for project completion screens owned by workflow modules.
///
/// Implementations provide the screen copy, project loading, completion
/// metrics, export action, and final completion command needed by
/// `ProjectCompletionView`.
@MainActor
public protocol ProjectCompletionViewModelType: AnyObject {
    /// Loaded scan summary used by completion metrics and module exports.
    var summary: ProjectScanSummary? { get }
    /// User-facing failure text for load, export, or completion operations.
    var errorMessage: String? { get set }
    /// User-facing confirmation after a successful export action.
    var successMessage: String? { get set }
    /// Controls the optional export-field customization sheet.
    var isCustomisingFields: Bool { get set }
    /// Module-provided screen copy and available actions.
    var configuration: ProjectCompletionConfiguration { get }
    /// Module-provided export fields, empty when the module has no configurable CSV export.
    var availableExportFields: [ProjectCompletionExportField] { get }

    /// Fetches the project represented by this completion screen.
    func fetchProject(modelContext: ModelContext) -> Project?
    /// Loads the persisted scan summary for metrics and module-specific exports.
    func loadSummary(modelContext: ModelContext)
    /// Returns persisted manual-audit decisions for the project.
    func auditDecisions(for project: Project, modelContext: ModelContext) -> [ManualAuditDecision]
    /// Builds completion metrics for the overview section.
    func metrics(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        appCoordinator: AppCoordinating
    ) -> [ProjectCompletionMetric]
    /// Returns ordered export fields from current, saved, or default selection.
    func activeExportFields() -> [ProjectCompletionExportField]
    /// Returns the ordered selected export field identifiers.
    func activeExportFieldIDs() -> [String]
    /// Persists the ordered export field identifiers for this module.
    func saveExportFieldIDs(_ fieldIDs: [String])
    /// Performs the optional module export action.
    func export(
        project: Project,
        decisions: [ManualAuditDecision],
        fields: [ProjectCompletionExportField],
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    )
    /// Marks the project complete and returns to the project library.
    func complete(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating)
    /// Deletes a project whose folder can no longer be loaded.
    func deleteUnavailableProject(_ project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating)
    /// Returns the display name registered for the project's module.
    func moduleName(for project: Project, appCoordinator: AppCoordinating) -> String
    /// Returns the stored completer name or the currently signed-in reviewer.
    func processedBy(for project: Project, appCoordinator: AppCoordinating) -> String
    /// Formats the minimum and maximum media duration from a scan summary.
    func durationRange(_ summary: ProjectScanSummary) -> String
}

/// Shared ViewModel implementation for module-owned project completion screens.
///
/// Modules subclass this type to provide localized configuration and optional
/// export behavior while reusing the generic loading, metrics, and completion
/// flow.
@Observable
@MainActor
open class ProjectCompletionViewModel: ProjectCompletionViewModelType {
    /// Loaded scan summary used by completion metrics and module exports.
    public private(set) var summary: ProjectScanSummary?
    /// User-facing failure text for load, export, or completion operations.
    public var errorMessage: String?
    /// User-facing confirmation after a successful export action.
    public var successMessage: String?
    /// Ordered export field identifiers selected during this screen session.
    public var selectedExportFieldIDs: [String]?
    /// Controls the optional export-field customization sheet.
    public var isCustomisingFields = false

    public let projectID: UUID
    public let projectScanService: ProjectScanServicing

    /// Creates completion state for a persisted project.
    public init(projectID: UUID, projectScanService: ProjectScanServicing) {
        self.projectID = projectID
        self.projectScanService = projectScanService
    }

    /// Module-provided screen copy and available actions.
    open var configuration: ProjectCompletionConfiguration {
        ProjectCompletionConfiguration(
            title: Strings.ProjectCompletion.title,
            subtitle: Strings.ProjectCompletion.subtitle,
            overviewTitle: Strings.ProjectCompletion.projectOverview,
            projectTitle: Strings.ProjectCompletion.project,
            processedByTitle: Strings.ProjectCompletion.processedBy,
            reviewedFilesTitle: Strings.ProjectCompletion.savedDecisions,
            validDecisionsTitle: "Valid",
            unsureDecisionsTitle: "Unsure",
            invalidDecisionsTitle: "Invalid",
            completeButtonTitle: Strings.ProjectCompletion.complete,
            backToProjectsButtonTitle: Strings.Common.backToProjects
        )
    }

    /// Module-provided export fields, empty when the module has no configurable CSV export.
    open var availableExportFields: [ProjectCompletionExportField] { [] }

    /// Fetches the project represented by this completion screen.
    public func fetchProject(modelContext: ModelContext) -> Project? {
        let projectID = projectID
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Loads the persisted scan summary for metrics and module-specific exports.
    public func loadSummary(modelContext: ModelContext) {
        guard let project = fetchProject(modelContext: modelContext) else {
            errorMessage = Strings.Common.projectNotFound
            return
        }

        project.normalizeWorkflowStatus()
        do {
            summary = try projectScanService.loadSummary(for: project)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns persisted manual-audit decisions for the project.
    public func auditDecisions(for project: Project, modelContext: ModelContext) -> [ManualAuditDecision] {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Builds generic completion metrics shared by every module.
    open func metrics(project: Project, summary: ProjectScanSummary, decisions: [ManualAuditDecision], appCoordinator: AppCoordinating) -> [ProjectCompletionMetric] {
        var values = [
            ProjectCompletionMetric(title: configuration.projectTitle, value: project.name),
            ProjectCompletionMetric(title: Strings.ProjectCompletion.type, value: moduleName(for: project, appCoordinator: appCoordinator)),
            ProjectCompletionMetric(title: configuration.processedByTitle, value: processedBy(for: project, appCoordinator: appCoordinator)),
            ProjectCompletionMetric(title: Strings.Common.status, value: statusTitle(for: project, appCoordinator: appCoordinator)),
            ProjectCompletionMetric(title: Strings.ProjectCompletion.inputFolder, value: project.rawInputFolderURL?.path ?? summary.inputFolder),
            ProjectCompletionMetric(title: "Total size", value: ByteCountFormatter.string(fromByteCount: Int64(summary.totalSizeBytes), countStyle: .file)),
            ProjectCompletionMetric(title: "Files", value: "\(summary.fileCount)"),
            ProjectCompletionMetric(title: "Duration range", value: durationRange(summary)),
            ProjectCompletionMetric(title: "Formats", value: summary.formats?.joined(separator: ", ") ?? Strings.Common.unknown),
            ProjectCompletionMetric(title: configuration.reviewedFilesTitle, value: "\(decisions.count)/\(summary.files.count)"),
            ProjectCompletionMetric(title: configuration.validDecisionsTitle, value: "\(decisions.filter { $0.decision == .valid }.count)"),
            ProjectCompletionMetric(title: configuration.unsureDecisionsTitle, value: "\(decisions.filter { $0.decision == .unsure }.count)"),
            ProjectCompletionMetric(title: configuration.invalidDecisionsTitle, value: "\(decisions.filter { $0.decision == .invalid }.count)")
        ]
        values.append(contentsOf: metadataMetrics(for: project))
        return values
    }

    /// Returns ordered export fields from current, saved, or default selection.
    public func activeExportFields() -> [ProjectCompletionExportField] {
        let fieldsByID = Dictionary(uniqueKeysWithValues: availableExportFields.map { ($0.id, $0) })
        return activeExportFieldIDs().compactMap { fieldsByID[$0] }
    }

    /// Returns the ordered selected export field identifiers.
    public func activeExportFieldIDs() -> [String] {
        if let selectedExportFieldIDs {
            return includingRequiredFields(selectedExportFieldIDs)
        }
        if let saved = UserDefaults.standard.stringArray(forKey: exportFieldDefaultsKey) {
            return includingRequiredFields(saved)
        }
        return availableExportFields.map(\.id)
    }

    /// Persists the ordered export field identifiers for this module.
    public func saveExportFieldIDs(_ fieldIDs: [String]) {
        selectedExportFieldIDs = includingRequiredFields(fieldIDs)
        UserDefaults.standard.set(selectedExportFieldIDs, forKey: exportFieldDefaultsKey)
    }

    /// Performs the optional module export action.
    open func export(
        project: Project,
        decisions: [ManualAuditDecision],
        fields: [ProjectCompletionExportField],
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    ) {}

    /// Marks the project complete and returns to the project library.
    public func complete(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating) {
        guard completeProject(project: project, modelContext: modelContext, appCoordinator: appCoordinator) else {
            return
        }
        appCoordinator.openProjectSelection()
    }

    /// Deletes a project whose folder can no longer be loaded.
    public func deleteUnavailableProject(_ project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating) {
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

    /// Returns the display name registered for the project's module.
    public func moduleName(for project: Project, appCoordinator: AppCoordinating) -> String {
        appCoordinator.moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))?.details.name ?? project.moduleID
    }

    /// Returns the stored completer name or the currently signed-in reviewer.
    public func processedBy(for project: Project, appCoordinator: AppCoordinating) -> String {
        guard let completedBy = project.completedBy?.trimmed, !completedBy.isEmpty else {
            return appCoordinator.userProfile?.name.trimmed.nilIfEmpty ?? Strings.Common.unknownUser
        }
        return completedBy
    }

    /// Formats the minimum and maximum media duration from a scan summary.
    public func durationRange(_ summary: ProjectScanSummary) -> String {
        guard let min = summary.durationMinSeconds, let max = summary.durationMaxSeconds else {
            return Strings.Common.unknown
        }

        return "\(formatDuration(min)) - \(formatDuration(max))"
    }

    /// Returns the localized workflow state shown in the project library.
    public func statusTitle(for project: Project, appCoordinator: AppCoordinating) -> String {
        guard let module = appCoordinator.moduleCatalog.module(for: ModuleID(rawValue: project.moduleID)) else {
            return project.workflowStatus.genericDisplayTitle
        }

        return module.projectSelectionPresentation(
            for: project,
            folderExists: ProjectSelectionViewModel.projectFolderExists(project),
            auditProgressText: Strings.ProjectSelection.zeroReviewed
        ).statusTitle
    }

    /// Converts module-owned setup metadata into generic presentation rows.
    public func metadataMetrics(for project: Project) -> [ProjectCompletionMetric] {
        project.metadataValues
            .sorted { $0.key < $1.key }
            .map { key, value in
                ProjectCompletionMetric(
                    title: Self.metadataTitle(for: key),
                    value: value.isEmpty ? Strings.Common.unknown : value
                )
            }
    }

    /// Records a successful export and saves completion metadata without navigating away.
    public func markExported(url: URL, project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating, message: String) {
        if completeProject(project: project, modelContext: modelContext, appCoordinator: appCoordinator) {
            successMessage = message
            errorMessage = nil
        }
    }

    @discardableResult
    private func completeProject(project: Project, modelContext: ModelContext, appCoordinator: AppCoordinating) -> Bool {
        guard let summary else { return false }
        project.workflowStatus = .completed
        project.completedBy = processedBy(for: project, appCoordinator: appCoordinator)
        project.lastOpenedAt = .now

        do {
            if let rootFolderURL = project.rootFolderURL {
                do {
                    try ProjectScanService.writeSummary(summary, projectRootURL: rootFolderURL)
                } catch {
                    AppLog.info("Project completion skipped scan summary refresh: \(error.localizedDescription)")
                }
            }
            try project.storeScanSummary(summary)
            try modelContext.save()
            try appCoordinator.dependencies.projectFileService.removeTemporaryArtifacts(for: project)
            return true
        } catch {
            errorMessage = Strings.ProjectCompletion.completionSaveFailed
            successMessage = nil
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

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private var exportFieldDefaultsKey: String {
        "pamflow.export.fields.\(String(describing: type(of: self)))"
    }

    private func includingRequiredFields(_ fieldIDs: [String]) -> [String] {
        let availableIDs = Set(availableExportFields.map(\.id))
        let selected = fieldIDs.filter { availableIDs.contains($0) }.uniqueStrings()
        let missingRequired = availableExportFields
            .filter { $0.isRequired && !selected.contains($0.id) }
            .map(\.id)
        return (missingRequired + selected).uniqueStrings()
    }

    private static func metadataTitle(for key: String) -> String {
        key.split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
