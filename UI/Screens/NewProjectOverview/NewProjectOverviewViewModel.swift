//
//  NewProjectOverviewViewModel.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation
import Core
import Observation
import SwiftData
import SwiftUI

private enum NewProjectOverviewFormat {
    public static let hertzSuffix = "Hz"
    public static let bitSuffix = "bit"
    public static let framesSuffix = "frames"
    public static let framesPerSecondSuffix = "fps"
    public static let secondsSuffix = "seconds"
    public static let newline = "\n"
    public static let comma = ", "
    public static let byteThresholdMedium = 2 * 1024 * 1024 * 1024
    public static let byteThresholdLarge = 10 * 1024 * 1024 * 1024
    public static let fileThresholdMedium = 100
    public static let fileThresholdLarge = 500
}

/// One metric shown in the new-project overview detail grid.
public struct NewProjectOverviewMetric: Identifiable, Equatable {
    public let title: String
    public let value: String

    public var id: String { "\(title)-\(value)" }

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

/// View-ready state for the new-project overview screen.
public struct NewProjectOverviewPresentation {
    public let project: Project
    public let summary: ProjectScanSummary
    public let moduleIconName: String
    public let highlightCount: String
    public let highlightTitle: String
    public let highlightMetrics: [HighlightMetric]
    public let detailMetrics: [NewProjectOverviewMetric]
    public let warnings: [String]
    public let showsWarnings: Bool
    public let moduleProcessingStatus: ModuleProcessingStatus
    public let primaryActionTitle: String
    public let isPrimaryActionDisabled: Bool
    public let canSkipManualAudit: Bool
    public let readinessText: String
    public let readinessColor: Color

    public enum ModuleProcessingStatus: Equatable {
        case hidden
        case preparing(String)
        case failed(String)
        case ready(String)
        case notice(String)
    }
}

/// Defines scan-summary presentation, reset actions, and workflow navigation for the project overview screen.
@MainActor
public protocol NewProjectOverviewViewModelType: AnyObject {
    /// Loaded scan summary for the project.
    var summary: ProjectScanSummary? { get }
    /// User-facing loading, reset, or workflow error.
    var errorMessage: String? { get }
    /// Indicates whether module-specific processing is running.
    var isPreparingModuleProcessing: Bool { get }
    /// Tracks whether module-specific processing has been attempted in this view lifetime.
    var didStartModuleProcessing: Bool { get }
    /// Successful or in-progress module processing status text.
    var moduleProcessingStatusMessage: String? { get }
    /// User-facing module processing failure.
    var moduleProcessingErrorMessage: String? { get }
    /// Screen title supplied by the active workflow module.
    var screenTitle: String { get }
    /// Screen subtitle supplied by the active workflow module.
    var screenSubtitle: String { get }

    /// Loads the project's persisted scan summary.
    func load(project: Project)
    /// Fetches a project by identifier from SwiftData.
    func fetchProject(_ projectID: UUID, modelContext: ModelContext) -> Project?
    /// Builds a view-ready presentation snapshot from the loaded summary.
    func presentation(project: Project, manualAuditProgress: String) -> NewProjectOverviewPresentation?
    /// Formats manual-audit progress using current persisted decisions.
    func manualAuditProgress(project: Project, total: Int, modelContext: ModelContext) -> String
    /// Counts persisted audit decisions for the project.
    func auditDecisionCount(for project: Project, modelContext: ModelContext) -> Int
    /// Returns whether module processing has generated a detections folder for the project.
    func hasGeneratedArtifacts(for project: Project, moduleCatalog: ModuleCatalog) -> Bool
    /// Deletes the project and its generated data before returning to module setup.
    func removeProjectAndReturnToSetup(project: Project, modelContext: ModelContext, coordinator: AppCoordinating)
    /// Clears manual-audit progress and returns to the previous scan step.
    func removeAuditProgressAndGoBackToScan(project: Project, modelContext: ModelContext, coordinator: AppCoordinating)
    /// Creates valid decisions for every scanned file and advances the workflow.
    func skipManualAudit(project: Project, modelContext: ModelContext, coordinator: AppCoordinating)
    /// Marks module-specific processing as started.
    func beginModuleProcessing()
    /// Marks module-specific processing as successful.
    func finishModuleProcessing()
    /// Stores module-specific processing failure text.
    func failModuleProcessing(_ error: Error)
    /// Performs the primary overview action and advances through module workflow.
    func performPrimaryAction(project: Project, modelContext: ModelContext, coordinator: AppCoordinating)
    /// Delegates back navigation to the app coordinator.
    func goBack(coordinator: AppCoordinating)
    /// Opens the owning module's setup screen.
    func openProjectSetup(for project: Project, coordinator: AppCoordinating)
    /// Opens the project selection screen.
    func openProjectSelection(coordinator: AppCoordinating)
    /// Advances the workflow after manual audit has been skipped.
    func continueAfterSkippingManualAudit(for project: Project, coordinator: AppCoordinating)
}

/// View model that turns scan results into project overview state and owns reset/skip actions.
@Observable
@MainActor
open class NewProjectOverviewViewModel: NewProjectOverviewViewModelType {
    /// Loaded scan summary for the project.
    public var summary: ProjectScanSummary?
    /// User-facing loading, reset, or workflow error.
    public var errorMessage: String?
    /// Indicates whether module-specific processing is running.
    public var isPreparingModuleProcessing = false
    /// Tracks whether module-specific processing has been attempted in this view lifetime.
    public var didStartModuleProcessing = false
    /// Successful or in-progress module processing status text.
    public var moduleProcessingStatusMessage: String?
    /// User-facing module processing failure.
    public var moduleProcessingErrorMessage: String?

    open var screenTitle: String {
        Strings.NewProjectOverview.title
    }

    open var screenSubtitle: String {
        Strings.NewProjectOverview.subtitle
    }

    /// Service used to load persisted scan summaries.
    public let projectScanService: ProjectScanServicing

    /// Creates a ViewModel that loads summaries and derives presentation state.
    public init(projectScanService: ProjectScanServicing) {
        self.projectScanService = projectScanService
    }

    /// Loads a persisted scan summary for the project.
    open func load(project: Project) {
        do {
            summary = try projectScanService.loadSummary(for: project)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func fetchProject(_ projectID: UUID, modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Builds the renderable overview state from current project, summary, and audit progress.
    public func presentation(project: Project, manualAuditProgress: String) -> NewProjectOverviewPresentation? {
        guard let summary else { return nil }

        let readiness = readiness(project: project, summary: summary)
        return NewProjectOverviewPresentation(
            project: project,
            summary: summary,
            moduleIconName: moduleIconName,
            highlightCount: "\(summary.fileCount)",
            highlightTitle: String(format: Strings.NewProjectOverview.filesFoundFormat, fileLabel),
            highlightMetrics: highlightMetrics(summary: summary, project: project, readiness: readiness),
            detailMetrics: detailMetrics(summary: summary, project: project, manualAuditProgress: manualAuditProgress),
            warnings: warnings(summary),
            showsWarnings: !summary.warnings.isEmpty || summary.qualityWarningCount > 0,
            moduleProcessingStatus: moduleProcessingStatus,
            primaryActionTitle: primaryActionTitle(project: project),
            isPrimaryActionDisabled: isPrimaryActionDisabled(project: project, summary: summary),
            canSkipManualAudit: canSkipManualAudit(project: project, summary: summary),
            readinessText: readiness.text,
            readinessColor: readiness.color
        )
    }

    public func manualAuditProgress(project: Project, total: Int, modelContext: ModelContext) -> String {
        guard total > 0 else {
            return String(format: Strings.NewProjectOverview.reviewedPercentFormat, 0, 0, 0)
        }

        let reviewed = auditDecisionCount(for: project, modelContext: modelContext)
        let percent = Int((Double(reviewed) / Double(total) * 100).rounded())
        return String(format: Strings.NewProjectOverview.reviewedPercentFormat, reviewed, total, percent)
    }

    public func auditDecisionCount(for project: Project, modelContext: ModelContext) -> Int {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }

    public func hasGeneratedArtifacts(for project: Project, moduleCatalog: ModuleCatalog) -> Bool {
        guard let rootFolderURL = project.rootFolderURL,
              let details = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))?.details else { return false }
        return details.generatedArtifactFolderNames.contains { folderName in
            generatedArtifactExists(named: folderName, in: rootFolderURL)
        }
    }

    private func generatedArtifactExists(named folderName: String, in rootFolderURL: URL) -> Bool {
        let detectionsURL = rootFolderURL.appendingPathComponent(folderName, isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: detectionsURL.path, isDirectory: &isDirectory) &&
            isDirectory.boolValue
    }

    public func removeProjectAndReturnToSetup(project: Project, modelContext: ModelContext, coordinator: AppCoordinating) {
        do {
            try coordinator.dependencies.projectFileService.deleteProjectFolder(for: project)
            deleteAuditDecisions(for: project, modelContext: modelContext)
            modelContext.delete(project)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        openProjectSetup(for: project, coordinator: coordinator)
    }

    public func removeAuditProgressAndGoBackToScan(project: Project, modelContext: ModelContext, coordinator: AppCoordinating) {
        deleteAuditDecisions(for: project, modelContext: modelContext)
        project.workflowStatus = .scanCompleted
        project.lastOpenedAt = .now
        try? modelContext.save()
        goBack(coordinator: coordinator)
    }

    public func skipManualAudit(project: Project, modelContext: ModelContext, coordinator: AppCoordinating) {
        guard let summary else { return }
        deleteAuditDecisions(for: project, modelContext: modelContext)
        for file in summary.files {
            modelContext.insert(
                ManualAuditDecision(
                    projectID: project.id,
                    fileRelativePath: file.relativePath,
                    decision: .valid
                )
            )
        }
        project.workflowStatus = .manualAuditCompleted
        project.lastOpenedAt = .now
        try? modelContext.save()
        continueAfterSkippingManualAudit(for: project, coordinator: coordinator)
    }

    /// Marks module-specific processing as started.
    public func beginModuleProcessing() {
        didStartModuleProcessing = true
        isPreparingModuleProcessing = true
        moduleProcessingStatusMessage = moduleProcessingPreparingText
        moduleProcessingErrorMessage = nil
    }

    /// Stores successful module processing state.
    public func finishModuleProcessing() {
        moduleProcessingStatusMessage = moduleProcessingReadyText
        moduleProcessingErrorMessage = nil
        isPreparingModuleProcessing = false
    }

    /// Stores failed module processing state.
    public func failModuleProcessing(_ error: Error) {
        moduleProcessingStatusMessage = nil
        moduleProcessingErrorMessage = error.localizedDescription
        isPreparingModuleProcessing = false
    }

    /// Performs the primary action's model decision and delegates navigation to the coordinator.
    public func performPrimaryAction(project: Project, modelContext: ModelContext, coordinator: AppCoordinating) {
        project.lastOpenedAt = .now
        try? modelContext.save()
        coordinator.goToNextStep(for: project)
    }

    /// Delegates back navigation when there is no destructive confirmation to show.
    public func goBack(coordinator: AppCoordinating) {
        coordinator.goBack()
    }

    /// Delegates navigation to the project setup screen for a removed project.
    public func openProjectSetup(for project: Project, coordinator: AppCoordinating) {
        coordinator.openModule(moduleID: ModuleID(rawValue: project.moduleID))
    }

    /// Delegates navigation to the project list when no project is available.
    public func openProjectSelection(coordinator: AppCoordinating) {
        coordinator.openProjectSelection()
    }

    /// Delegates navigation after skipping manual audit.
    public func continueAfterSkippingManualAudit(for project: Project, coordinator: AppCoordinating) {
        coordinator.goToNextStep(for: project)
    }

    open var moduleIconName: String {
        Icons.folder
    }

    open var fileLabel: String {
        Strings.NewProjectOverview.filesFound
    }

    open var showsModuleProcessingStatus: Bool {
        false
    }

    open var moduleProcessingPreparingText: String {
        Strings.NewProjectOverview.processingInProgress
    }

    open var moduleProcessingReadyText: String {
        Strings.NewProjectOverview.ready
    }

    open var moduleProcessingReadyNoticeText: String {
        Strings.NewProjectOverview.ready
    }

    open var moduleProcessingStatus: NewProjectOverviewPresentation.ModuleProcessingStatus {
        guard showsModuleProcessingStatus else { return .hidden }
        if isPreparingModuleProcessing {
            return .preparing(moduleProcessingStatusMessage ?? moduleProcessingPreparingText)
        }
        if let moduleProcessingErrorMessage {
            return .failed(moduleProcessingErrorMessage)
        }
        if let moduleProcessingStatusMessage {
            return .ready(moduleProcessingStatusMessage)
        }
        return .notice(moduleProcessingReadyNoticeText)
    }

    open func highlightMetrics(
        summary: ProjectScanSummary,
        project: Project,
        readiness: (text: String, color: Color)
    ) -> [HighlightMetric] {
        var metrics = [
            HighlightMetric(
                Strings.NewProjectOverview.totalSize,
                ByteCountFormatter.string(fromByteCount: Int64(summary.totalSizeBytes), countStyle: .file)
            )
        ]

        metrics.append(HighlightMetric(
            Strings.NewProjectOverview.attention,
            attentionText(summary),
            valueColor: summary.qualityWarningCount == 0 ? AppColors.success : AppColors.error
        ))
        metrics.append(HighlightMetric(
            Strings.Common.status,
            summary.fileCount > 0 ? readiness.text : Strings.NewProjectOverview.notReady,
            valueColor: summary.fileCount > 0 ? readiness.color : AppColors.error
        ))
        return metrics
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

    open func detailMetrics(
        summary: ProjectScanSummary,
        project: Project,
        manualAuditProgress: String
    ) -> [NewProjectOverviewMetric] {
        var metrics = [
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.projectName, value: project.name),
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.recorderID, value: project.metadataSummaryValue ?? Strings.NewProjectOverview.unknown),
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.filesFound, value: "\(summary.fileCount)"),
            NewProjectOverviewMetric(
                title: Strings.NewProjectOverview.totalSize,
                value: ByteCountFormatter.string(fromByteCount: Int64(summary.totalSizeBytes), countStyle: .file)
            )
        ]
        metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.estimatedBatchSize, value: estimatedBatchSize(summary)))
        return metrics
    }

    private func warnings(_ summary: ProjectScanSummary) -> [String] {
        var warnings = summary.warnings
        if summary.qualityWarningCount > 0 {
            warnings.append(String(format: Strings.NewProjectOverview.filesNeedAttentionFormat, summary.qualityWarningCount))
        }
        return warnings
    }

    open func primaryActionTitle(project: Project) -> String {
        switch project.workflowStatus {
        case .manualAuditInProgress:
            return Strings.NewProjectOverview.continueManualAuditButton
        case .manualAuditCompleted:
            return Strings.NewProjectOverview.openManualAuditOverviewButton
        default:
            return Strings.NewProjectOverview.startManualAuditButton
        }
    }

    open func isPrimaryActionDisabled(project: Project, summary: ProjectScanSummary) -> Bool {
        guard summary.fileCount > 0 else { return true }
        return false
    }

    open func canSkipManualAudit(project: Project, summary: ProjectScanSummary) -> Bool {
        false
    }

    open func readiness(
        project: Project,
        summary: ProjectScanSummary
    ) -> (text: String, color: Color) {
        guard summary.fileCount > 0 else {
            return (Strings.NewProjectOverview.notReady, AppColors.error)
        }

        return (Strings.NewProjectOverview.ready, AppColors.success)
    }

    private func attentionText(_ summary: ProjectScanSummary) -> String {
        summary.qualityWarningCount == 0
            ? Strings.NewProjectOverview.noFilesNeedAttention
            : String(format: Strings.NewProjectOverview.filesNeedAttentionPlainFormat, summary.qualityWarningCount)
    }

    public func durationRange(_ summary: ProjectScanSummary) -> String {
        guard let min = summary.durationMinSeconds, let max = summary.durationMaxSeconds else {
            return Strings.NewProjectOverview.unknown
        }

        return "\(formatDuration(min)) - \(formatDuration(max))"
    }

    public func estimatedBatchSize(_ summary: ProjectScanSummary) -> String {
        if summary.fileCount >= NewProjectOverviewFormat.fileThresholdLarge ||
            summary.totalSizeBytes >= NewProjectOverviewFormat.byteThresholdLarge {
            return Strings.NewProjectOverview.largeBatch
        }

        if summary.fileCount >= NewProjectOverviewFormat.fileThresholdMedium ||
            summary.totalSizeBytes >= NewProjectOverviewFormat.byteThresholdMedium {
            return Strings.NewProjectOverview.mediumBatch
        }

        return Strings.NewProjectOverview.smallBatch
    }

    public func formattedInts(_ values: [Int], suffix: String? = nil) -> String {
        guard !values.isEmpty else { return Strings.NewProjectOverview.unknown }

        return values
            .map { value in
                if let suffix {
                    return "\(value) \(suffix)"
                }
                return "\(value)"
            }
            .joined(separator: NewProjectOverviewFormat.comma)
    }

    public func formattedStrings(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else { return Strings.NewProjectOverview.unknown }
        return values.joined(separator: NewProjectOverviewFormat.comma)
    }

    public func formatDuration(_ seconds: Double) -> String {
        if seconds >= 60 {
            return "\(Int(seconds.rounded())) \(NewProjectOverviewFormat.secondsSuffix)"
        }

        return String(format: "%.1f \(NewProjectOverviewFormat.secondsSuffix)", seconds)
    }
}
