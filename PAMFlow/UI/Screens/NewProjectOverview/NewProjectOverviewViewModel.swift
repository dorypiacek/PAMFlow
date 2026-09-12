//
//  NewProjectOverviewViewModel.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation
import Observation
import SwiftData
import SwiftUI

private enum NewProjectOverviewFormat {
    static let hertzSuffix = "Hz"
    static let bitSuffix = "bit"
    static let framesSuffix = "frames"
    static let framesPerSecondSuffix = "fps"
    static let secondsSuffix = "seconds"
    static let newline = "\n"
    static let comma = ", "
    static let byteThresholdMedium = 2 * 1024 * 1024 * 1024
    static let byteThresholdLarge = 10 * 1024 * 1024 * 1024
    static let fileThresholdMedium = 100
    static let fileThresholdLarge = 500
}

/// One metric shown in the new-project overview detail grid.
struct NewProjectOverviewMetric: Identifiable, Equatable {
    let title: String
    let value: String

    var id: String { "\(title)-\(value)" }
}

/// View-ready state for the new-project overview screen.
struct NewProjectOverviewPresentation {
    let project: Project
    let summary: ProjectScanSummary
    let module: WorkflowModule
    let moduleIconName: String
    let highlightCount: String
    let highlightTitle: String
    let highlightMetrics: [HighlightMetric]
    let detailMetrics: [NewProjectOverviewMetric]
    let warnings: [String]
    let showsWarnings: Bool
    let showsSharkTrackStatus: Bool
    let sharkTrackStatus: SharkTrackStatus
    let primaryActionTitle: String
    let isPrimaryActionDisabled: Bool
    let canSkipManualAudit: Bool
    let readinessText: String
    let readinessColor: Color

    enum SharkTrackStatus: Equatable {
        case hidden
        case preparing(String)
        case failed(String)
        case ready(String)
        case notice(String)
    }
}

/// Defines scan-summary presentation, reset actions, and workflow navigation for the project overview screen.
@MainActor
protocol NewProjectOverviewViewModelType: AnyObject {
    /// Loaded scan summary for the project.
    var summary: ProjectScanSummary? { get }
    /// User-facing loading, reset, or workflow error.
    var errorMessage: String? { get }
    /// Indicates whether SharkTrack preparation is running.
    var isPreparingSharkTrack: Bool { get }
    /// Tracks whether SharkTrack preparation has been attempted in this view lifetime.
    var didStartSharkTrack: Bool { get }
    /// Successful or in-progress SharkTrack status text.
    var sharkTrackStatusMessage: String? { get }
    /// User-facing SharkTrack preparation failure.
    var sharkTrackErrorMessage: String? { get }

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
    func hasGeneratedDetections(for project: Project) -> Bool
    /// Deletes the project and its generated data before returning to module setup.
    func removeProjectAndReturnToSetup(project: Project, modelContext: ModelContext, coordinator: AppCoordinating)
    /// Clears manual-audit progress and returns to the previous scan step.
    func removeAuditProgressAndGoBackToScan(project: Project, modelContext: ModelContext, coordinator: AppCoordinating)
    /// Creates valid decisions for every scanned file and advances the workflow.
    func skipManualAudit(project: Project, modelContext: ModelContext, coordinator: AppCoordinating)
    /// Warms initial audio previews so the first manual-audit samples open quickly.
    func prewarmInitialAudioPreviews(project: Project, audioPreviewCacheService: AudioPreviewCacheServicing)
    /// Marks SharkTrack preparation as started.
    func beginSharkTrackPreparation()
    /// Marks SharkTrack preparation as successful.
    func finishSharkTrackPreparation()
    /// Stores SharkTrack preparation failure text.
    func failSharkTrackPreparation(_ error: Error)
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
final class NewProjectOverviewViewModel: NewProjectOverviewViewModelType {
    /// Loaded scan summary for the project.
    var summary: ProjectScanSummary?
    /// User-facing loading, reset, or workflow error.
    var errorMessage: String?
    /// Indicates whether SharkTrack preparation is running.
    var isPreparingSharkTrack = false
    /// Tracks whether SharkTrack preparation has been attempted in this view lifetime.
    var didStartSharkTrack = false
    /// Successful or in-progress SharkTrack status text.
    var sharkTrackStatusMessage: String?
    /// User-facing SharkTrack preparation failure.
    var sharkTrackErrorMessage: String?

    /// Service used to load persisted scan summaries.
    private let projectScanService: ProjectScanServicing

    /// Creates a ViewModel that loads summaries and derives presentation state.
    init(projectScanService: ProjectScanServicing) {
        self.projectScanService = projectScanService
    }

    /// Loads a persisted scan summary for the project.
    func load(project: Project) {
        do {
            summary = try projectScanService.loadSummary(for: project)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchProject(_ projectID: UUID, modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Builds the renderable overview state from current project, summary, and audit progress.
    func presentation(project: Project, manualAuditProgress: String) -> NewProjectOverviewPresentation? {
        guard let summary else { return nil }

        let module = WorkflowModule.module(for: project.moduleID)
        let readiness = readiness(project: project, summary: summary, module: module)
        return NewProjectOverviewPresentation(
            project: project,
            summary: summary,
            module: module,
            moduleIconName: moduleIconName(for: module),
            highlightCount: "\(summary.fileCount)",
            highlightTitle: String(format: Strings.NewProjectOverview.filesFoundFormat, fileLabel(for: module)),
            highlightMetrics: highlightMetrics(summary: summary, module: module, readiness: readiness),
            detailMetrics: detailMetrics(summary: summary, project: project, module: module, manualAuditProgress: manualAuditProgress),
            warnings: warnings(summary),
            showsWarnings: !summary.warnings.isEmpty || summary.qualityWarningCount > 0,
            showsSharkTrackStatus: module.requiresSharkTrack,
            sharkTrackStatus: sharkTrackStatus(module: module),
            primaryActionTitle: primaryActionTitle(project: project, module: module),
            isPrimaryActionDisabled: isPrimaryActionDisabled(project: project, summary: summary, module: module),
            canSkipManualAudit: canSkipManualAudit(project: project, summary: summary, module: module),
            readinessText: readiness.text,
            readinessColor: readiness.color
        )
    }

    func manualAuditProgress(project: Project, total: Int, modelContext: ModelContext) -> String {
        guard total > 0 else {
            return String(format: Strings.NewProjectOverview.reviewedPercentFormat, 0, 0, 0)
        }

        let reviewed = auditDecisionCount(for: project, modelContext: modelContext)
        let percent = Int((Double(reviewed) / Double(total) * 100).rounded())
        return String(format: Strings.NewProjectOverview.reviewedPercentFormat, reviewed, total, percent)
    }

    func auditDecisionCount(for project: Project, modelContext: ModelContext) -> Int {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }

    func hasGeneratedDetections(for project: Project) -> Bool {
        guard let rootFolderURL = project.rootFolderURL else { return false }
        let detectionsURL = rootFolderURL.appendingPathComponent(ProjectFileNames.detectionsDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: detectionsURL.path, isDirectory: &isDirectory) &&
            isDirectory.boolValue
    }

    func removeProjectAndReturnToSetup(project: Project, modelContext: ModelContext, coordinator: AppCoordinating) {
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

    func removeAuditProgressAndGoBackToScan(project: Project, modelContext: ModelContext, coordinator: AppCoordinating) {
        deleteAuditDecisions(for: project, modelContext: modelContext)
        project.workflowStatus = .scanCompleted
        project.lastOpenedAt = .now
        try? modelContext.save()
        goBack(coordinator: coordinator)
    }

    func skipManualAudit(project: Project, modelContext: ModelContext, coordinator: AppCoordinating) {
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

    func prewarmInitialAudioPreviews(project: Project, audioPreviewCacheService: AudioPreviewCacheServicing) {
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio,
              let summary,
              let inputFolderURL = project.inputFolderURL else {
            return
        }

        for file in summary.files.prefix(Metrics.Cache.manualAuditPrewarmCount + 1) where isSupportedAudioPath(file.relativePath) {
            let url = inputFolderURL.appendingPathComponent(file.relativePath)
            audioPreviewCacheService.preheat(
                url: url,
                securityScopedURL: inputFolderURL,
                clipStartSeconds: nil,
                clipDurationSeconds: nil
            )
        }
    }

    /// Marks SharkTrack preparation as started.
    func beginSharkTrackPreparation() {
        didStartSharkTrack = true
        isPreparingSharkTrack = true
        sharkTrackStatusMessage = Strings.NewProjectOverview.sharkTrackPreparing
        sharkTrackErrorMessage = nil
    }

    /// Stores successful SharkTrack preparation state.
    func finishSharkTrackPreparation() {
        sharkTrackStatusMessage = Strings.NewProjectOverview.sharkTrackReady
        sharkTrackErrorMessage = nil
        isPreparingSharkTrack = false
    }

    /// Stores failed SharkTrack preparation state.
    func failSharkTrackPreparation(_ error: Error) {
        sharkTrackStatusMessage = nil
        sharkTrackErrorMessage = error.localizedDescription
        isPreparingSharkTrack = false
    }

    /// Performs the primary action's model decision and delegates navigation to the coordinator.
    func performPrimaryAction(project: Project, modelContext: ModelContext, coordinator: AppCoordinating) {
        project.lastOpenedAt = .now
        try? modelContext.save()
        coordinator.goToNextStep(for: project)
    }

    /// Delegates back navigation when there is no destructive confirmation to show.
    func goBack(coordinator: AppCoordinating) {
        coordinator.goBack()
    }

    /// Delegates navigation to the project setup screen for a removed project.
    func openProjectSetup(for project: Project, coordinator: AppCoordinating) {
        coordinator.openModule(moduleID: ModuleID(rawValue: project.moduleID))
    }

    /// Delegates navigation to the project list when no project is available.
    func openProjectSelection(coordinator: AppCoordinating) {
        coordinator.openProjectSelection()
    }

    /// Delegates navigation after skipping manual audit.
    func continueAfterSkippingManualAudit(for project: Project, coordinator: AppCoordinating) {
        coordinator.goToNextStep(for: project)
    }

    private func highlightMetrics(
        summary: ProjectScanSummary,
        module: WorkflowModule,
        readiness: (text: String, color: Color)
    ) -> [HighlightMetric] {
        var metrics = [
            HighlightMetric(
                Strings.NewProjectOverview.totalSize,
                ByteCountFormatter.string(fromByteCount: Int64(summary.totalSizeBytes), countStyle: .file)
            )
        ]

        if module == .pamAudio {
            metrics.append(HighlightMetric(
                Strings.NewProjectOverview.sampleRates,
                formattedInts(summary.sampleRatesHz, suffix: NewProjectOverviewFormat.hertzSuffix)
            ))
            metrics.append(HighlightMetric(Strings.NewProjectOverview.channels, formattedInts(summary.channelCounts)))
            metrics.append(HighlightMetric(
                Strings.NewProjectOverview.typicalLength,
                summary.durationModeSeconds.map(formatDuration) ?? Strings.NewProjectOverview.unknown
            ))
        } else {
            metrics.append(HighlightMetric(Strings.NewProjectOverview.formats, formattedStrings(summary.formats)))
            metrics.append(HighlightMetric(Strings.NewProjectOverview.resolutions, formattedStrings(summary.resolutions)))
            if module == .bruvVideo {
                metrics.append(HighlightMetric(Strings.NewProjectOverview.frameRates, frameRates(summary)))
            }
        }

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

    private func isSupportedAudioPath(_ path: String) -> Bool {
        MediaFileExtensions.previewAudio.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private func detailMetrics(
        summary: ProjectScanSummary,
        project: Project,
        module: WorkflowModule,
        manualAuditProgress: String
    ) -> [NewProjectOverviewMetric] {
        var metrics = [
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.projectName, value: project.name),
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.recorderID, value: project.metadataOpcode ?? Strings.NewProjectOverview.unknown),
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.filesFound, value: "\(summary.fileCount)"),
            NewProjectOverviewMetric(
                title: Strings.NewProjectOverview.totalSize,
                value: ByteCountFormatter.string(fromByteCount: Int64(summary.totalSizeBytes), countStyle: .file)
            )
        ]

        switch module {
        case .pamAudio:
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.durationRange, value: durationRange(summary)))
            metrics.append(NewProjectOverviewMetric(
                title: Strings.NewProjectOverview.sampleRates,
                value: formattedInts(summary.sampleRatesHz, suffix: NewProjectOverviewFormat.hertzSuffix)
            ))
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.channels, value: formattedInts(summary.channelCounts)))
            metrics.append(NewProjectOverviewMetric(
                title: Strings.NewProjectOverview.bitDepths,
                value: formattedInts(summary.bitDepths, suffix: NewProjectOverviewFormat.bitSuffix)
            ))
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.manualAuditProgress, value: manualAuditProgress))

        case .bruvVideo:
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.durationRange, value: durationRange(summary)))
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.formats, value: formattedStrings(summary.formats)))
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.resolutions, value: formattedStrings(summary.resolutions)))
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.frameRates, value: frameRates(summary)))
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.frameCountRange, value: frameCountRange(summary)))

        case .ruvImages:
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.formats, value: formattedStrings(summary.formats)))
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.resolutions, value: formattedStrings(summary.resolutions)))
            metrics.append(NewProjectOverviewMetric(title: Strings.NewProjectOverview.imageCount, value: "\(summary.fileCount)"))
        }

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

    private func primaryActionTitle(project: Project, module: WorkflowModule) -> String {
        if module.requiresSharkTrack, project.workflowStatus == .scanCompleted {
            return Strings.NewProjectOverview.startProcessingButton
        }

        switch project.workflowStatus {
        case .manualAuditInProgress:
            return module.requiresSharkTrack ? Strings.NewProjectOverview.continueFrameReviewButton : Strings.NewProjectOverview.continueManualAuditButton
        case .manualAuditCompleted:
            return module.requiresSharkTrack ? Strings.NewProjectOverview.openFrameReviewOverviewButton : Strings.NewProjectOverview.openManualAuditOverviewButton
        default:
            return module.requiresSharkTrack
                ? Strings.NewProjectOverview.startFrameReviewButton
                : Strings.NewProjectOverview.startManualAuditButton
        }
    }

    private func isPrimaryActionDisabled(project: Project, summary: ProjectScanSummary, module: WorkflowModule) -> Bool {
        guard summary.fileCount > 0 else { return true }
        if module.requiresSharkTrack, project.workflowStatus == .scanCompleted {
            return false
        }
        return module.requiresSharkTrack && sharkTrackErrorMessage != nil
    }

    private func canSkipManualAudit(project: Project, summary: ProjectScanSummary, module: WorkflowModule) -> Bool {
        module == .pamAudio && summary.fileCount > 0 && project.workflowStatus != .manualAuditCompleted
    }

    private func readiness(
        project: Project,
        summary: ProjectScanSummary,
        module: WorkflowModule
    ) -> (text: String, color: Color) {
        guard summary.fileCount > 0 else {
            return (Strings.NewProjectOverview.notReady, AppColors.error)
        }

        if module.requiresSharkTrack {
            if isPreparingSharkTrack {
                return (Strings.NewProjectOverview.processingInProgress, AppColors.success)
            }
            if sharkTrackErrorMessage != nil {
                return (Strings.NewProjectOverview.processingBlocked, AppColors.error)
            }
            if project.workflowStatus == .scanCompleted {
                return (Strings.NewProjectOverview.readyForProcessing, AppColors.success)
            }
        }

        return (Strings.NewProjectOverview.ready, AppColors.success)
    }

    private func sharkTrackStatus(module: WorkflowModule) -> NewProjectOverviewPresentation.SharkTrackStatus {
        guard module.requiresSharkTrack else { return .hidden }
        if isPreparingSharkTrack {
            return .preparing(sharkTrackStatusMessage ?? Strings.NewProjectOverview.sharkTrackPreparing)
        }
        if let sharkTrackErrorMessage {
            return .failed(sharkTrackErrorMessage)
        }
        if let sharkTrackStatusMessage {
            return .ready(sharkTrackStatusMessage)
        }
        return .notice(Strings.NewProjectOverview.sharkTrackReadyNotice)
    }

    private func fileLabel(for module: WorkflowModule) -> String {
        switch module {
        case .pamAudio:
            Strings.NewProjectOverview.wavFiles
        case .bruvVideo:
            Strings.NewProjectOverview.videoFiles
        case .ruvImages:
            Strings.NewProjectOverview.imageFiles
        }
    }

    private func moduleIconName(for module: WorkflowModule) -> String {
        switch module {
        case .pamAudio:
            Icons.audio
        case .bruvVideo:
            Icons.video
        case .ruvImages:
            Icons.image
        }
    }

    private func attentionText(_ summary: ProjectScanSummary) -> String {
        summary.qualityWarningCount == 0
            ? Strings.NewProjectOverview.noFilesNeedAttention
            : String(format: Strings.NewProjectOverview.filesNeedAttentionPlainFormat, summary.qualityWarningCount)
    }

    private func durationRange(_ summary: ProjectScanSummary) -> String {
        guard let min = summary.durationMinSeconds, let max = summary.durationMaxSeconds else {
            return Strings.NewProjectOverview.unknown
        }

        return "\(formatDuration(min)) - \(formatDuration(max))"
    }

    private func frameRates(_ summary: ProjectScanSummary) -> String {
        let values = summary.files
            .compactMap(\.frameRate)
            .map { ($0 * 10).rounded() / 10 }
        guard !values.isEmpty else { return Strings.NewProjectOverview.unknown }

        return Array(Set(values))
            .sorted()
            .map { value in
                let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(value))"
                    : String(format: "%.1f", value)
                return "\(formatted) \(NewProjectOverviewFormat.framesPerSecondSuffix)"
            }
            .joined(separator: NewProjectOverviewFormat.comma)
    }

    private func frameCountRange(_ summary: ProjectScanSummary) -> String {
        guard let min = summary.frameCountMin, let max = summary.frameCountMax else {
            return Strings.NewProjectOverview.unknown
        }

        return min == max
            ? "\(min) \(NewProjectOverviewFormat.framesSuffix)"
            : "\(min) - \(max) \(NewProjectOverviewFormat.framesSuffix)"
    }

    private func estimatedBatchSize(_ summary: ProjectScanSummary) -> String {
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

    private func formattedInts(_ values: [Int], suffix: String? = nil) -> String {
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

    private func formattedStrings(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else { return Strings.NewProjectOverview.unknown }
        return values.joined(separator: NewProjectOverviewFormat.comma)
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds >= 60 {
            return "\(Int(seconds.rounded())) \(NewProjectOverviewFormat.secondsSuffix)"
        }

        return String(format: "%.1f \(NewProjectOverviewFormat.secondsSuffix)", seconds)
    }
}
