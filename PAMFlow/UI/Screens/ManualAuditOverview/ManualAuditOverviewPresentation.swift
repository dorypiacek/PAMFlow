//
//  ManualAuditOverviewSnapshot.swift
//  PAMFlow
//
//  Created by Dory on 12/08/2026.
//

import Foundation

/// Testable, view-ready state for the manual audit overview screen.
///
/// `ManualAuditOverviewView` should render this as a snapshot rather than recalculate
/// audit counts, species summaries, and media grouping directly in SwiftUI.
struct ManualAuditOverviewPresentation {
    /// One grouped breakdown row shown in expandable overview cards.
    struct CountRow: Identifiable, Equatable {
        let name: String
        let total: Int
        let confirmed: Int

        var id: String { name }
        var progressText: String { "\(confirmed)/\(total)" }
    }

    /// One species count row shown in the species summary card.
    struct SpeciesRow: Identifiable, Equatable {
        let species: String
        let count: Int

        var id: String { species }
    }

    /// One label/value metric rendered in the overview details card.
    struct Metric: Identifiable, Equatable {
        let title: String
        let value: String

        var id: String { "\(title)-\(value)" }
    }

    let project: Project
    let summary: ProjectScanSummary
    let module: WorkflowModule
    let decisions: [ManualAuditDecision]
    let isPAMGuardDetectionReview: Bool

    /// Creates a deterministic overview snapshot from persisted scan and audit data.
    init(project: Project, summary: ProjectScanSummary, decisions allDecisions: [ManualAuditDecision]) {
        self.project = project
        self.summary = summary
        self.module = WorkflowModule.module(for: project.moduleID)
        self.isPAMGuardDetectionReview = summary.files.contains { $0.sharkTrackStatus == ProjectScanStatus.pamguard }

        let summaryFilePaths = Set(summary.files.map(\.relativePath))
        self.decisions = Self.latestDecisionsByFile(
            allDecisions.filter { summaryFilePaths.contains($0.fileRelativePath) }
        )
    }

    var reviewedCount: Int { decisions.count }
    var totalCount: Int { summary.files.count }
    var validCount: Int { decisionCount(.valid) }
    var invalidCount: Int { decisionCount(.invalid) }
    var remainingCount: Int { max(totalCount - reviewedCount, 0) }
    var confirmedDetectionCount: Int { confirmedDecisions.count }
    var isComplete: Bool { totalCount == 0 || reviewedCount == totalCount }
    var readyMetricTitle: String {
        module.usesPAMGuard && !isPAMGuardDetectionReview
            ? Strings.ManualAuditOverview.readyForPamguard
            : Strings.ManualAuditOverview.readyForExport
    }
    var readyMetricValue: String {
        isComplete ? Strings.Common.yes : Strings.Common.notYet
    }
    var title: String {
        if isPAMGuardDetectionReview {
            return Strings.ManualAuditOverview.audioDetectionTitle
        }

        return module.requiresSharkTrack
            ? Strings.ManualAuditOverview.frameReviewTitle
            : Strings.ManualAuditOverview.title
    }
    var subtitle: String {
        isPAMGuardDetectionReview
            ? Strings.ManualAuditOverview.audioDetectionSubtitle
            : Strings.ManualAuditOverview.subtitle
    }
    var primaryActionTitle: String {
        if !isComplete {
            return Strings.ManualAuditOverview.reviewDetections
        }

        if isPAMGuardDetectionReview {
            return Strings.ManualAuditOverview.continueToReport
        }

        return module.usesPAMGuard ? Strings.ManualAuditOverview.goToPamguardSetup : Strings.ManualAuditOverview.continueToReport
    }
    var primaryActionHelp: String {
        if !isComplete {
            return Strings.ManualAuditOverview.reviewDetectionsHelp
        }

        if isPAMGuardDetectionReview {
            return Strings.ManualAuditOverview.reportHelp
        }

        return module.usesPAMGuard ? Strings.ManualAuditOverview.preparePamguardHelp : Strings.ManualAuditOverview.reportHelp
    }
    var opensCompletionFromPrimaryAction: Bool {
        isComplete && (isPAMGuardDetectionReview || !module.usesPAMGuard)
    }

    /// Metrics shown in the details card for the current workflow stage.
    var detailMetrics: [Metric] {
        var metrics: [Metric] = []

        if isPAMGuardDetectionReview {
            metrics.append(Metric(title: Strings.ManualAuditOverview.originalDetections, value: "\(summary.files.count)"))
            metrics.append(Metric(title: Strings.ManualAuditOverview.confirmedDetections, value: "\(confirmedDetectionCount)"))
            metrics.append(contentsOf: audioDetectionMetrics)
            metrics.append(contentsOf: projectMetadataMetrics)
        } else if module.requiresSharkTrack {
            metrics.append(Metric(title: Strings.ManualAuditOverview.originalDetections, value: "\(summary.files.count)"))
            metrics.append(Metric(title: Strings.ManualAuditOverview.confirmedDetections, value: "\(confirmedDetectionCount)"))
            metrics.append(contentsOf: sharkTrackMetrics)
            if module.usesProjectMetadata {
                metrics.append(contentsOf: projectMetadataMetrics)
            }
        } else if module.usesPAMGuard {
            metrics.append(contentsOf: pamSampleMetrics)
            metrics.append(contentsOf: projectMetadataMetrics)
        }

        return metrics
    }

    /// Rows for SharkTrack video/image detection grouping.
    var mediaBreakdownRows: [CountRow] {
        groupedRows { sourceMediaDisplayName(for: $0) }
    }

    /// Rows for PAMGuard detection grouping by source recording.
    var audioRecordingRows: [CountRow] {
        groupedRows { $0.sourceVideo ?? Strings.Common.unknown }
    }

    /// Species counts for valid, exportable detections.
    var speciesRows: [SpeciesRow] {
        let counts = confirmedDecisions.reduce(into: [String: Int]()) { partialResult, decision in
            for species in preferredSpeciesNames(for: decision) {
                partialResult[species, default: 0] += 1
            }
        }

        return counts
            .map { SpeciesRow(species: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.species.localizedStandardCompare($1.species) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    /// Counts matching a decision value.
    func decisionCount(_ value: ManualAuditDecisionValue) -> Int {
        decisions.filter { $0.decision == value }.count
    }

    private var confirmedDecisions: [ManualAuditDecision] {
        decisions.filter { $0.decision == .valid && $0.isRemovedFromExport != true }
    }

    private var pamSampleMetrics: [Metric] {
        var metrics = [
            Metric(title: Strings.ManualAuditOverview.originalSamples, value: "\(summary.files.count)"),
            Metric(title: Strings.ManualAuditOverview.validSamples, value: "\(decisionCount(.valid))")
        ]

        let invalidReasons = reasonCounts(decisions.filter { $0.decision == .invalid })
        if !invalidReasons.isEmpty {
            metrics.append(Metric(
                title: Strings.ManualAuditOverview.invalidReasons,
                value: invalidReasons.map { "\($0.reason): \($0.count)" }.joined(separator: ", ")
            ))
        }

        return metrics
    }

    private var audioDetectionMetrics: [Metric] {
        var metrics: [Metric] = []
        let sourceRecordings = uniqueValues(summary.files.compactMap(\.sourceVideo))
        if !sourceRecordings.isEmpty {
            metrics.append(Metric(title: Strings.ManualAuditOverview.sourceRecordings, value: "\(sourceRecordings.count)"))
        }

        let tables = uniqueValues(summary.files.compactMap(\.format))
        if !tables.isEmpty {
            metrics.append(Metric(title: Strings.ManualAuditOverview.detectionTables, value: tables.joined(separator: ", ")))
        }
        return metrics
    }

    private var sharkTrackMetrics: [Metric] {
        var metrics: [Metric] = []
        let sourceVideos = uniqueValues(summary.files.map(sourceMediaDisplayName(for:)))
        if !sourceVideos.isEmpty {
            metrics.append(Metric(title: Strings.ManualAuditOverview.processedVideos, value: "\(sourceVideos.count)"))
        }

        let formats = uniqueValues(summary.files.compactMap(\.format))
        if !formats.isEmpty {
            metrics.append(Metric(title: Strings.ManualAuditOverview.formats, value: formats.joined(separator: ", ")))
        }

        let imageSizes = uniqueValues(summary.files.compactMap { file -> String? in
            guard let width = file.width, let height = file.height else { return nil }
            return "\(width) x \(height)"
        })
        if !imageSizes.isEmpty {
            metrics.append(Metric(title: Strings.ManualAuditOverview.imageSize, value: imageSizes.joined(separator: ", ")))
        }
        return metrics
    }

    private var projectMetadataMetrics: [Metric] {
        var metrics = [
            Metric(title: Strings.ProjectSetup.opcode, value: project.metadataOpcode ?? Strings.Common.unknown),
            Metric(
                title: module == .pamAudio ? Strings.ProjectSetup.dateDeployed : Strings.ProjectSetup.date,
                value: project.metadataDate ?? Strings.Common.unknown
            )
        ]
        if module == .pamAudio {
            metrics.append(Metric(title: Strings.ProjectSetup.dateRetrieved, value: project.metadataDateRetrieved ?? Strings.Common.unknown))
        }
        metrics.append(Metric(title: Strings.ProjectSetup.location, value: project.metadataLocation ?? Strings.Common.unknown))
        metrics.append(Metric(title: Strings.ProjectSetup.depth, value: project.metadataDepth ?? Strings.Common.unknown))
        if let bottomType = project.metadataBottomType {
            metrics.append(Metric(title: Strings.ProjectSetup.bottomType, value: bottomType))
        }
        if module != .pamAudio, let waterTemperature = project.metadataWaterTemperature {
            metrics.append(Metric(title: Strings.ProjectSetup.waterTemperature, value: waterTemperature))
        }
        return metrics
    }

    private func groupedRows(named name: (ProjectScanFile) -> String) -> [CountRow] {
        let decisionByPath = Dictionary(uniqueKeysWithValues: decisions.map { ($0.fileRelativePath, $0) })
        let counts = summary.files.reduce(into: [String: (total: Int, confirmed: Int)]()) { partialResult, file in
            let groupName = name(file)
            let decision = decisionByPath[file.relativePath]
            partialResult[groupName, default: (0, 0)].total += 1
            if decision?.decision == .valid && decision?.isRemovedFromExport != true {
                partialResult[groupName, default: (0, 0)].confirmed += 1
            }
        }

        return counts
            .map { CountRow(name: $0.key, total: $0.value.total, confirmed: $0.value.confirmed) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func reasonCounts(_ decisions: [ManualAuditDecision]) -> [(reason: String, count: Int)] {
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

    private func preferredSpeciesNames(for decision: ManualAuditDecision) -> [String] {
        if let data = decision.speciesSelectionsJSON?.data(using: .utf8),
           let selections = try? JSONDecoder().decode([SpeciesSelection].self, from: data),
           !selections.isEmpty {
            return selections.map(\.fullName).map(\.trimmed).filter { !$0.isEmpty }
        }

        let genusSpecies = [decision.speciesGenus, decision.speciesName]
            .compactMap { $0 }
            .joined(separator: " ")
        let candidates: [String?] = [
            decision.speciesFullName,
            genusSpecies.isEmpty ? nil : genusSpecies,
            decision.speciesName,
            decision.speciesGenus,
            decision.speciesFamily
        ]

        let species = candidates
            .map { ($0 ?? "").trimmed }
            .first { !$0.isEmpty }
        return species.map { [$0] } ?? []
    }

    private func sourceMediaDisplayName(for file: ProjectScanFile) -> String {
        if let sourceVideo = file.sourceVideo, !sourceVideo.isEmpty {
            return sourceVideo
        }

        let components = file.relativePath.split(separator: "/").map(String.init)
        if let internalResultsIndex = components.firstIndex(of: "internal_results"),
           components.indices.contains(internalResultsIndex + 1) {
            return components[internalResultsIndex + 1]
        }

        return isSharkTrackOutputName(file.fileName) ? Strings.Common.unknown : file.fileName
    }

    private func isSharkTrackOutputName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("elasmobranch") || lowercased.contains("sharktrack")
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func latestDecisionsByFile(_ decisions: [ManualAuditDecision]) -> [ManualAuditDecision] {
        let latestByPath = decisions.reduce(into: [String: ManualAuditDecision]()) { partialResult, decision in
            guard let existing = partialResult[decision.fileRelativePath] else {
                partialResult[decision.fileRelativePath] = decision
                return
            }

            let existingDate = existing.updatedAt ?? existing.createdAt
            let decisionDate = decision.updatedAt ?? decision.createdAt
            if decisionDate >= existingDate {
                partialResult[decision.fileRelativePath] = decision
            }
        }

        return latestByPath.values.sorted {
            $0.fileRelativePath.localizedStandardCompare($1.fileRelativePath) == .orderedAscending
        }
    }
}
