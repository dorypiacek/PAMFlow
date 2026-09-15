//
//  PAMManualAuditOverviewViewModel.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import UI
import Core
import SwiftData

/// Manual-audit overview behavior for audio samples and PAMGuard detections.
@MainActor
@Observable
final class PAMManualAuditOverviewViewModel: ManualAuditOverviewViewModel {
    private static let preheatedPreviewCount = 5

    private let audioPreviewCacheService: AudioPreviewCacheServicing?

    init(
        projectID: UUID,
        projectScanService: ProjectScanServicing,
        audioPreviewCacheService: AudioPreviewCacheServicing? = nil
    ) {
        self.audioPreviewCacheService = audioPreviewCacheService
        super.init(projectID: projectID, projectScanService: projectScanService)
    }

    override func load(modelContext: ModelContext) {
        super.load(modelContext: modelContext)
        guard let overview = overviewModel(modelContext: modelContext) else { return }
        preheatInitialPreviews(project: overview.project, summary: overview.summary)
    }

    override func completePrimaryAction(
        modelContext: ModelContext,
        overview: ManualAuditOverviewPresentation,
        coordinator: AppCoordinating
    ) throws {
        if !overview.isComplete || overview.configuration.opensCompletionWhenComplete {
            try super.completePrimaryAction(modelContext: modelContext, overview: overview, coordinator: coordinator)
            return
        }

        overview.project.workflowStatus = .pamguardSetupReady
        overview.project.lastOpenedAt = .now
        try modelContext.save()
        coordinator.goToNextStep(for: overview.project)
    }

    override func overviewConfiguration(
        project: Project,
        summary: ProjectScanSummary
    ) -> ManualAuditOverviewPresentation.Configuration {
        summary.files.contains { $0.pamDetectionStatus == PAMScanStatus.pamguard }
            ? Self.detectionConfiguration
            : Self.sampleConfiguration
    }

    override func inProgressStatus(for overview: ManualAuditOverviewPresentation) -> ProjectWorkflowStatus {
        overview.configuration.opensCompletionWhenComplete ? .detectionReviewInProgress : .manualAuditInProgress
    }

    private static let sampleConfiguration = ManualAuditOverviewPresentation.Configuration(
        title: Strings.ManualAuditOverview.title,
        subtitle: Strings.ManualAuditOverview.subtitle,
        showsSpeciesBreakdown: false,
        countBreakdownTitle: Strings.ManualAuditOverview.decisionBreakdown,
        readyMetricTitle: PAMStrings.Overview.readyForPamguard,
        incompletePrimaryActionTitle: Strings.ManualAuditOverview.reviewDetections,
        completePrimaryActionTitle: PAMStrings.Overview.goToPamguardSetup,
        incompletePrimaryActionHelp: Strings.ManualAuditOverview.reviewDetectionsHelp,
        completePrimaryActionHelp: PAMStrings.Overview.preparePamguardHelp,
        opensCompletionWhenComplete: false,
        countGroupName: { $0.fileName },
        detailMetrics: { project, summary, decisions in
            var metrics = [
                ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.originalSamples, value: "\(summary.files.count)"),
                ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.validSamples, value: "\(decisions.filter { $0.decision == .valid }.count)")
            ]
            let invalidReasons = reasonCounts(decisions.filter { $0.decision == .invalid })
            if !invalidReasons.isEmpty {
                metrics.append(ManualAuditOverviewPresentation.Metric(
                    title: Strings.ManualAuditOverview.invalidReasons,
                    value: invalidReasons.map { "\($0.reason): \($0.count)" }.joined(separator: ", ")
                ))
            }
            metrics.append(contentsOf: metadataMetrics(project: project))
            return metrics
        }
    )

    private static let detectionConfiguration = ManualAuditOverviewPresentation.Configuration(
        title: PAMStrings.Overview.audioDetectionTitle,
        subtitle: PAMStrings.Overview.audioDetectionSubtitle,
        showsSpeciesBreakdown: true,
        countBreakdownTitle: Strings.ManualAuditOverview.detectionsByRecording,
        readyMetricTitle: Strings.ManualAuditOverview.readyForExport,
        incompletePrimaryActionTitle: Strings.ManualAuditOverview.reviewDetections,
        completePrimaryActionTitle: Strings.ManualAuditOverview.continueToReport,
        incompletePrimaryActionHelp: Strings.ManualAuditOverview.reviewDetectionsHelp,
        completePrimaryActionHelp: Strings.ManualAuditOverview.reportHelp,
        opensCompletionWhenComplete: true,
        countGroupName: { $0.pamSourceMedia ?? Strings.Common.unknown },
        detailMetrics: { project, summary, decisions in
            var metrics = [
                ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.originalDetections, value: "\(summary.files.count)"),
                ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.confirmedDetections, value: "\(decisions.filter { $0.decision == .valid && $0.isRemovedFromExport != true }.count)")
            ]
            let sourceRecordings = ManualAuditOverviewPresentation.uniqueValues(summary.files.compactMap(\.pamSourceMedia))
            if !sourceRecordings.isEmpty {
                metrics.append(ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.sourceRecordings, value: "\(sourceRecordings.count)"))
            }
            let tables = ManualAuditOverviewPresentation.uniqueValues(summary.files.compactMap(\.format))
            if !tables.isEmpty {
                metrics.append(ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.detectionTables, value: tables.joined(separator: ", ")))
            }
            metrics.append(contentsOf: metadataMetrics(project: project))
            return metrics
        }
    )

    private static func reasonCounts(_ decisions: [ManualAuditDecision]) -> [(reason: String, count: Int)] {
        let counts = decisions.reduce(into: [String: Int]()) { partialResult, decision in
            let reason = decision.notes.trimmed
            guard !reason.isEmpty else { return }
            partialResult[reason, default: 0] += 1
        }
        return counts
            .map { (reason: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.reason.localizedStandardCompare($1.reason) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    private static func metadataMetrics(project: Project) -> [ManualAuditOverviewPresentation.Metric] {
        project.metadataValues
            .sorted { $0.key < $1.key }
            .map { key, value in
                ManualAuditOverviewPresentation.Metric(
                    title: key
                        .split(separator: "_")
                        .map { $0.capitalized }
                        .joined(separator: " "),
                    value: value.isEmpty ? Strings.Common.unknown : value
                )
            }
    }

    private func preheatInitialPreviews(project: Project, summary: ProjectScanSummary) {
        guard let audioPreviewCacheService else { return }

        for file in summary.files.prefix(Self.preheatedPreviewCount) {
            guard let url = playbackURL(project: project, file: file) else {
                continue
            }
            audioPreviewCacheService.preheat(
                url: url,
                securityScopedURL: securityScopedURL(for: url, project: project),
                clipStartSeconds: clipStartSeconds(for: file, summary: summary),
                clipDurationSeconds: clipDurationSeconds(for: file, summary: summary)
            )
        }
    }

    private func playbackURL(project: Project, file: ProjectScanFile) -> URL? {
        let sourcePath = file.pamSourceMedia ?? file.relativePath
        let candidateURL = URL(fileURLWithPath: sourcePath)
        if candidateURL.isFileURL,
           candidateURL.path.hasPrefix("/"),
           PAMMediaFileExtensions.previewAudio.contains(candidateURL.pathExtension.lowercased()),
           FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        for baseURL in [project.inputFolderURL, project.rawInputFolderURL, project.rootFolderURL].compactMap({ $0 }).uniqueStandardizedURLs() {
            let url = baseURL.appendingPathComponent(sourcePath)
            if PAMMediaFileExtensions.previewAudio.contains(url.pathExtension.lowercased()),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func securityScopedURL(for url: URL, project: Project) -> URL {
        [project.inputFolderURL, project.rawInputFolderURL, project.rootFolderURL]
            .compactMap { $0 }
            .first { url.path.hasPrefix($0.path) }
            ?? project.inputFolderURL
            ?? url
    }

    private func clipStartSeconds(for file: ProjectScanFile, summary: ProjectScanSummary) -> Double? {
        summary.files.contains { $0.pamDetectionStatus == PAMScanStatus.pamguard }
            ? max(0, file.clipStartSeconds ?? 0)
            : nil
    }

    private func clipDurationSeconds(for file: ProjectScanFile, summary: ProjectScanSummary) -> Double? {
        summary.files.contains { $0.pamDetectionStatus == PAMScanStatus.pamguard }
            ? max(0.05, file.clipDurationSeconds ?? file.durationSeconds ?? 1)
            : nil
    }
}
