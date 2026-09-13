//
//  BRUVManualAuditOverviewViewModel.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation

/// Manual-audit overview behavior for visual detections.
@MainActor
@Observable
final class BRUVManualAuditOverviewViewModel: ManualAuditOverviewViewModel {
    override func overviewConfiguration(
        project: Project,
        summary: ProjectScanSummary
    ) -> ManualAuditOverviewPresentation.Configuration {
        Self.visualConfiguration
    }

    private static let visualConfiguration = ManualAuditOverviewPresentation.Configuration(
        title: Strings.ManualAuditOverview.frameReviewTitle,
        subtitle: Strings.ManualAuditOverview.subtitle,
        showsSpeciesBreakdown: true,
        countBreakdownTitle: Strings.ManualAuditOverview.detectionsByVideo,
        readyMetricTitle: Strings.ManualAuditOverview.readyForExport,
        incompletePrimaryActionTitle: Strings.ManualAuditOverview.reviewDetections,
        completePrimaryActionTitle: Strings.ManualAuditOverview.continueToReport,
        incompletePrimaryActionHelp: Strings.ManualAuditOverview.reviewDetectionsHelp,
        completePrimaryActionHelp: Strings.ManualAuditOverview.reportHelp,
        opensCompletionWhenComplete: true,
        countGroupName: { sourceMediaDisplayName(for: $0) },
        detailMetrics: { project, summary, decisions in
            var metrics = [
                ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.originalDetections, value: "\(summary.files.count)"),
                ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.confirmedDetections, value: "\(decisions.filter { $0.decision == .valid && $0.isRemovedFromExport != true }.count)")
            ]
            let sourceVideos = ManualAuditOverviewPresentation.uniqueValues(summary.files.map(sourceMediaDisplayName(for:)))
            if !sourceVideos.isEmpty {
                metrics.append(ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.processedVideos, value: "\(sourceVideos.count)"))
            }
            let formats = ManualAuditOverviewPresentation.uniqueValues(summary.files.compactMap(\.format))
            if !formats.isEmpty {
                metrics.append(ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.formats, value: formats.joined(separator: ", ")))
            }
            let imageSizes = ManualAuditOverviewPresentation.uniqueValues(summary.files.compactMap { file -> String? in
                guard let width = file.width, let height = file.height else { return nil }
                return "\(width) x \(height)"
            })
            if !imageSizes.isEmpty {
                metrics.append(ManualAuditOverviewPresentation.Metric(title: Strings.ManualAuditOverview.imageSize, value: imageSizes.joined(separator: ", ")))
            }
            metrics.append(contentsOf: metadataMetrics(project: project))
            return metrics
        }
    )

    private static func sourceMediaDisplayName(for file: ProjectScanFile) -> String {
        if let sourceVideo = file.sourceVideo, !sourceVideo.isEmpty {
            return sourceVideo
        }

        let components = file.relativePath.split(separator: "/").map(String.init)
        if let internalResultsIndex = components.firstIndex(of: "internal_results"),
           components.indices.contains(internalResultsIndex + 1) {
            return components[internalResultsIndex + 1]
        }

        return isGeneratedVisualOutputName(file.fileName) ? Strings.Common.unknown : file.fileName
    }

    private static func isGeneratedVisualOutputName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("elasmobranch") || lowercased.contains("sharktrack")
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
}
