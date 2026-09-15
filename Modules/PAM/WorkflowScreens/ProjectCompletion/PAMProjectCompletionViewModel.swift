//
//  PAMProjectCompletionViewModel.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Core
import Foundation
import Observation
import SwiftData
import UI

/// ViewModel for the PAM workflow completion screen.
///
/// The ViewModel owns loading the generic scan summary, collecting persisted
/// manual-audit decisions, exporting the PAMGuard package, and marking the
/// project as complete. Keeping those commands here lets the SwiftUI view stay
/// render-focused while the PAM module keeps control of its export behaviour.
@Observable
@MainActor
final class PAMProjectCompletionViewModel: ProjectCompletionViewModel {
    override var configuration: ProjectCompletionConfiguration {
        ProjectCompletionConfiguration(
            title: PAMStrings.Completion.title,
            subtitle: PAMStrings.Completion.subtitle,
            overviewTitle: PAMStrings.Completion.projectOverview,
            projectTitle: PAMStrings.Completion.project,
            processedByTitle: PAMStrings.Completion.processedBy,
            reviewedFilesTitle: PAMStrings.Completion.reviewedFiles,
            validDecisionsTitle: PAMStrings.Completion.validDecisions,
            unsureDecisionsTitle: PAMStrings.Completion.unsureDecisions,
            invalidDecisionsTitle: PAMStrings.Completion.invalidDecisions,
            completeButtonTitle: PAMStrings.Completion.complete,
            backToProjectsButtonTitle: PAMStrings.Completion.backToProjects,
            exportButtonTitle: PAMStrings.Completion.exportPackage
        )
    }

    override func metrics(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        appCoordinator: AppCoordinating
    ) -> [ProjectCompletionMetric] {
        var metrics = super.metrics(project: project, summary: summary, decisions: decisions, appCoordinator: appCoordinator)
        metrics.append(contentsOf: [
            ProjectCompletionMetric(title: Strings.ExportFields.sampleRateHz, value: summary.sampleRatesHz.map { "\($0) Hz" }.joined(separator: ", ").nilIfEmpty ?? Strings.Common.unknown),
            ProjectCompletionMetric(title: Strings.ExportFields.channels, value: summary.channelCounts.map(String.init).joined(separator: ", ").nilIfEmpty ?? Strings.Common.unknown),
            ProjectCompletionMetric(title: Strings.ExportFields.bitDepth, value: summary.bitDepths.map { "\($0) bit" }.joined(separator: ", ").nilIfEmpty ?? Strings.Common.unknown),
            ProjectCompletionMetric(title: "Source recordings", value: "\(Set(summary.files.compactMap(\.pamSourceMedia)).count)")
        ])
        return metrics
    }

    /// Exports the PAMGuard package to a user-selected destination.
    override func export(
        project: Project,
        decisions: [ManualAuditDecision],
        fields: [ProjectCompletionExportField],
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    ) {
        guard let summary else { return }
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
            markExported(
                url: url,
                project: project,
                modelContext: modelContext,
                appCoordinator: appCoordinator,
                message: String(format: PAMStrings.Completion.exportSuccessFormat, url.lastPathComponent)
            )
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }
}
