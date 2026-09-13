//
//  PAMProjectOverviewViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import SwiftUI

/// Audio project overview behavior layered on top of the shared overview ViewModel.
@Observable
@MainActor
final class PAMProjectOverviewViewModel: NewProjectOverviewViewModel {
    /// Service used to prepare cached audio snippets for manual audit.
    private let audioPreviewCacheService: AudioPreviewCacheServicing

    /// Creates an audio-aware overview ViewModel with shared scan loading and preview caching services.
    init(
        projectScanService: ProjectScanServicing,
        audioPreviewCacheService: AudioPreviewCacheServicing
    ) {
        self.audioPreviewCacheService = audioPreviewCacheService
        super.init(projectScanService: projectScanService)
    }

    override var moduleIconName: String {
        Icons.audio
    }

    override var fileLabel: String {
        Strings.NewProjectOverview.wavFiles
    }

    /// Loads the shared scan summary and warms the first audio previews for manual audit.
    override func load(project: Project) {
        super.load(project: project)
        guard let summary,
              let inputFolderURL = project.inputFolderURL else {
            return
        }

        let previewableExtensions = PAMMediaFileExtensions.previewAudio
        for file in summary.files.prefix(Metrics.Cache.manualAuditPrewarmCount + 1)
            where previewableExtensions.contains(URL(fileURLWithPath: file.relativePath).pathExtension.lowercased()) {
            audioPreviewCacheService.preheat(
                url: inputFolderURL.appendingPathComponent(file.relativePath),
                securityScopedURL: inputFolderURL,
                clipStartSeconds: nil,
                clipDurationSeconds: nil
            )
        }
    }

    override func highlightMetrics(
        summary: ProjectScanSummary,
        project: Project,
        readiness: (text: String, color: Color)
    ) -> [HighlightMetric] {
        var metrics = super.highlightMetrics(summary: summary, project: project, readiness: readiness)
        metrics.insert(
            HighlightMetric(
                Strings.NewProjectOverview.sampleRates,
                formattedInts(summary.sampleRatesHz, suffix: "Hz")
            ),
            at: min(1, metrics.count)
        )
        metrics.insert(
            HighlightMetric(Strings.NewProjectOverview.channels, formattedInts(summary.channelCounts)),
            at: min(2, metrics.count)
        )
        metrics.insert(
            HighlightMetric(
                Strings.NewProjectOverview.typicalLength,
                summary.durationModeSeconds.map(formatDuration) ?? Strings.NewProjectOverview.unknown
            ),
            at: min(3, metrics.count)
        )
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
        metrics.insert(contentsOf: [
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.durationRange, value: durationRange(summary)),
            NewProjectOverviewMetric(
                title: Strings.NewProjectOverview.sampleRates,
                value: formattedInts(summary.sampleRatesHz, suffix: "Hz")
            ),
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.channels, value: formattedInts(summary.channelCounts)),
            NewProjectOverviewMetric(
                title: Strings.NewProjectOverview.bitDepths,
                value: formattedInts(summary.bitDepths, suffix: "bit")
            ),
            NewProjectOverviewMetric(title: Strings.NewProjectOverview.manualAuditProgress, value: manualAuditProgress)
        ], at: max(0, metrics.count - 1))
        return metrics
    }

    override func canSkipManualAudit(project: Project, summary: ProjectScanSummary) -> Bool {
        summary.fileCount > 0 && project.workflowStatus != .manualAuditCompleted
    }
}
