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

    /// Module-provided copy and metric hooks for rendering an overview.
    struct Configuration {
        let title: String
        let subtitle: String
        let showsSpeciesBreakdown: Bool
        let countBreakdownTitle: String
        let readyMetricTitle: String
        let incompletePrimaryActionTitle: String
        let completePrimaryActionTitle: String
        let incompletePrimaryActionHelp: String
        let completePrimaryActionHelp: String
        let opensCompletionWhenComplete: Bool
        let countGroupName: (ProjectScanFile) -> String
        let detailMetrics: (Project, ProjectScanSummary, [ManualAuditDecision]) -> [Metric]

        static let generic = Configuration(
            title: Strings.ManualAuditOverview.title,
            subtitle: Strings.ManualAuditOverview.subtitle,
            showsSpeciesBreakdown: false,
            countBreakdownTitle: Strings.ManualAuditOverview.decisionBreakdown,
            readyMetricTitle: Strings.ManualAuditOverview.readyForExport,
            incompletePrimaryActionTitle: Strings.ManualAuditOverview.reviewDetections,
            completePrimaryActionTitle: Strings.ManualAuditOverview.continueToReport,
            incompletePrimaryActionHelp: Strings.ManualAuditOverview.reviewDetectionsHelp,
            completePrimaryActionHelp: Strings.ManualAuditOverview.reportHelp,
            opensCompletionWhenComplete: true,
            countGroupName: { $0.fileName },
            detailMetrics: { project, summary, decisions in
                var metrics = [
                    Metric(title: Strings.ManualAuditOverview.originalSamples, value: "\(summary.files.count)"),
                    Metric(title: Strings.ManualAuditOverview.validSamples, value: "\(decisions.filter { $0.decision == .valid }.count)")
                ]
                metrics.append(contentsOf: project.metadataValues
                    .sorted { $0.key < $1.key }
                    .map { key, value in
                        Metric(
                            title: key
                                .split(separator: "_")
                                .map { $0.capitalized }
                                .joined(separator: " "),
                            value: value.isEmpty ? Strings.Common.unknown : value
                        )
                    })
                return metrics
            }
        )
    }

    let project: Project
    let summary: ProjectScanSummary
    let decisions: [ManualAuditDecision]
    let configuration: Configuration

    /// Creates a deterministic overview snapshot from persisted scan and audit data.
    init(
        project: Project,
        summary: ProjectScanSummary,
        decisions allDecisions: [ManualAuditDecision],
        configuration: Configuration
    ) {
        self.project = project
        self.summary = summary
        self.configuration = configuration

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
    var showsSpeciesBreakdown: Bool {
        configuration.showsSpeciesBreakdown
    }
    var countBreakdownTitle: String {
        configuration.countBreakdownTitle
    }
    var countBreakdownRows: [CountRow] {
        groupedRows(named: configuration.countGroupName)
    }
    var readyMetricTitle: String {
        configuration.readyMetricTitle
    }
    var readyMetricValue: String {
        isComplete ? Strings.Common.yes : Strings.Common.notYet
    }
    var title: String {
        configuration.title
    }
    var subtitle: String {
        configuration.subtitle
    }
    var primaryActionTitle: String {
        if !isComplete {
            return configuration.incompletePrimaryActionTitle
        }
        return configuration.completePrimaryActionTitle
    }
    var primaryActionHelp: String {
        if !isComplete {
            return configuration.incompletePrimaryActionHelp
        }
        return configuration.completePrimaryActionHelp
    }
    var opensCompletionFromPrimaryAction: Bool {
        isComplete && configuration.opensCompletionWhenComplete
    }

    /// Metrics shown in the details card for the current workflow stage.
    var detailMetrics: [Metric] {
        configuration.detailMetrics(project, summary, decisions)
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

    static func uniqueValues(_ values: [String]) -> [String] {
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
