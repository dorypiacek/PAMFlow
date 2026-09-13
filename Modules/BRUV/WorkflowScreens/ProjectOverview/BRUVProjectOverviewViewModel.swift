//
//  BRUVProjectOverviewViewModel.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import SwiftUI

/// Visual project overview behavior layered on top of the shared overview ViewModel.
@Observable
@MainActor
final class BRUVProjectOverviewViewModel: NewProjectOverviewViewModel {
    private let projectType: BRUVProjectType

    /// Creates a visual-project overview ViewModel with shared scan loading and
    /// BRUV/RUV-specific processing presentation.
    init(projectScanService: ProjectScanServicing, projectType: BRUVProjectType) {
        self.projectType = projectType
        super.init(projectScanService: projectScanService)
    }

    override var moduleIconName: String {
        switch projectType {
        case .bruv:
            Icons.video
        case .ruv:
            Icons.image
        }
    }

    override var fileLabel: String {
        switch projectType {
        case .bruv:
            Strings.NewProjectOverview.videoFiles
        case .ruv:
            Strings.NewProjectOverview.imageFiles
        }
    }

    override var showsModuleProcessingStatus: Bool {
        true
    }

    override var moduleProcessingPreparingText: String {
        BRUVStrings.Overview.preparing
    }

    override var moduleProcessingReadyText: String {
        BRUVStrings.Overview.ready
    }

    override var moduleProcessingReadyNoticeText: String {
        BRUVStrings.Overview.readyNotice
    }

    override func highlightMetrics(
        summary: ProjectScanSummary,
        project: Project,
        readiness: (text: String, color: Color)
    ) -> [HighlightMetric] {
        var metrics = super.highlightMetrics(summary: summary, project: project, readiness: readiness)
        metrics.insert(
            HighlightMetric(Strings.NewProjectOverview.formats, formattedStrings(summary.formats)),
            at: min(1, metrics.count)
        )
        metrics.insert(
            HighlightMetric(Strings.NewProjectOverview.resolutions, formattedStrings(summary.resolutions)),
            at: min(2, metrics.count)
        )
        if projectType == .bruv {
            metrics.insert(
                HighlightMetric(Strings.NewProjectOverview.frameRates, frameRates(summary)),
                at: min(3, metrics.count)
            )
        }
        return metrics
    }

    override func detailMetrics(
        summary: ProjectScanSummary,
        project: Project,
        manualAuditProgress: String
    ) -> [NewProjectOverviewMetric] {
        var metrics = super.detailMetrics(
            summary: summary,
            project: project,
            manualAuditProgress: manualAuditProgress
        )
        let visualMetrics: [NewProjectOverviewMetric]
        switch projectType {
        case .bruv:
            visualMetrics = [
                NewProjectOverviewMetric(title: Strings.NewProjectOverview.durationRange, value: durationRange(summary)),
                NewProjectOverviewMetric(title: Strings.NewProjectOverview.formats, value: formattedStrings(summary.formats)),
                NewProjectOverviewMetric(title: Strings.NewProjectOverview.resolutions, value: formattedStrings(summary.resolutions)),
                NewProjectOverviewMetric(title: Strings.NewProjectOverview.frameRates, value: frameRates(summary)),
                NewProjectOverviewMetric(title: Strings.NewProjectOverview.frameCountRange, value: frameCountRange(summary))
            ]
        case .ruv:
            visualMetrics = [
                NewProjectOverviewMetric(title: Strings.NewProjectOverview.formats, value: formattedStrings(summary.formats)),
                NewProjectOverviewMetric(title: Strings.NewProjectOverview.resolutions, value: formattedStrings(summary.resolutions)),
                NewProjectOverviewMetric(title: Strings.NewProjectOverview.imageCount, value: "\(summary.fileCount)")
            ]
        }
        metrics.insert(contentsOf: visualMetrics, at: max(0, metrics.count - 1))
        return metrics
    }

    override func primaryActionTitle(project: Project) -> String {
        if project.workflowStatus == .scanCompleted {
            return Strings.NewProjectOverview.startProcessingButton
        }

        switch project.workflowStatus {
        case .manualAuditInProgress:
            return Strings.NewProjectOverview.continueFrameReviewButton
        case .manualAuditCompleted:
            return Strings.NewProjectOverview.openFrameReviewOverviewButton
        default:
            return Strings.NewProjectOverview.startFrameReviewButton
        }
    }

    override func isPrimaryActionDisabled(project: Project, summary: ProjectScanSummary) -> Bool {
        guard summary.fileCount > 0 else { return true }
        if project.workflowStatus == .scanCompleted {
            return false
        }
        return moduleProcessingErrorMessage != nil
    }

    override func readiness(project: Project, summary: ProjectScanSummary) -> (text: String, color: Color) {
        guard summary.fileCount > 0 else {
            return (Strings.NewProjectOverview.notReady, AppColors.error)
        }

        if isPreparingModuleProcessing {
            return (Strings.NewProjectOverview.processingInProgress, AppColors.success)
        }
        if moduleProcessingErrorMessage != nil {
            return (Strings.NewProjectOverview.processingBlocked, AppColors.error)
        }
        if project.workflowStatus == .scanCompleted {
            return (Strings.NewProjectOverview.readyForProcessing, AppColors.success)
        }
        return (Strings.NewProjectOverview.ready, AppColors.success)
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
                return "\(formatted) fps"
            }
            .joined(separator: ", ")
    }

    private func frameCountRange(_ summary: ProjectScanSummary) -> String {
        guard let min = summary.frameCountMin, let max = summary.frameCountMax else {
            return Strings.NewProjectOverview.unknown
        }

        return min == max ? "\(min) frames" : "\(min) - \(max) frames"
    }
}
