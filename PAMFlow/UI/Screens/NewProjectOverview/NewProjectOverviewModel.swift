//
//  NewProjectOverviewModel.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation
import Observation
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

/// Loads scan summary state for the new-project overview screen.
@Observable
@MainActor
final class NewProjectOverviewModel {
    var summary: ProjectScanSummary?
    var errorMessage: String?
    var isPreparingSharkTrack = false
    var didStartSharkTrack = false
    var sharkTrackStatusMessage: String?
    var sharkTrackErrorMessage: String?

    private let projectScanService: ProjectScanServicing

    /// Creates a model that loads summaries and derives presentation state.
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
    func performPrimaryAction(project: Project, coordinator: AppCoordinating) {
        project.lastOpenedAt = .now
        let module = WorkflowModule.module(for: project.moduleID)
        if module.requiresSharkTrack, project.workflowStatus == .scanCompleted {
            coordinator.openSharkTrackProcessing(project)
            return
        }

        if project.workflowStatus == .manualAuditCompleted {
            coordinator.openManualAuditOverview(project)
            return
        }

        project.workflowStatus = .manualAuditInProgress
        coordinator.openManualAudit(project, startAtLastReviewed: false)
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

    /// Delegates navigation to PAMGuard setup after a skipped audio audit.
    func openPAMGuardSetup(for project: Project, coordinator: AppCoordinating) {
        coordinator.openPAMGuardSetup(project)
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
