//
//  ManualAuditOverviewSnapshot.swift
//  PAMFlow
//
//  Created by Dory on 12/08/2026.
//

import Foundation
import Core

/// Testable, view-ready state for the manual audit overview screen.
///
/// `ManualAuditOverviewView` should render this as a snapshot rather than recalculate
/// audit counts, species summaries, and media grouping directly in SwiftUI.
public struct ManualAuditOverviewPresentation {
    /// One grouped breakdown row shown in expandable overview cards.
    public struct CountRow: Identifiable, Equatable {
        public let name: String
        public let total: Int
        public let confirmed: Int

        public var id: String { name }
        public var progressText: String { "\(confirmed)/\(total)" }
    }

    /// One species count row shown in the species summary card.
    public struct SpeciesRow: Identifiable, Equatable {
        public let species: String
        public let count: Int

        public var id: String { species }
    }

    /// One label/value metric rendered in the overview details card.
    public struct Metric: Identifiable, Equatable {
        public let title: String
        public let value: String

        public var id: String { "\(title)-\(value)" }

        public init(title: String, value: String) {
            self.title = title
            self.value = value
        }
    }

    /// Module-provided copy and metric hooks for rendering an overview.
    public struct Configuration: @unchecked Sendable {
        public let title: String
        public let subtitle: String
        public let showsSpeciesBreakdown: Bool
        public let countBreakdownTitle: String
        public let readyMetricTitle: String
        public let incompletePrimaryActionTitle: String
        public let completePrimaryActionTitle: String
        public let secondaryActionTitle: String?
        public let incompletePrimaryActionHelp: String
        public let completePrimaryActionHelp: String
        public let opensCompletionWhenComplete: Bool
        public let countGroupName: (ProjectScanFile) -> String
        public let detailMetrics: (Project, ProjectScanSummary, [ManualAuditDecision]) -> [Metric]

        public init(
            title: String,
            subtitle: String,
            showsSpeciesBreakdown: Bool,
            countBreakdownTitle: String,
            readyMetricTitle: String,
            incompletePrimaryActionTitle: String,
            completePrimaryActionTitle: String,
            secondaryActionTitle: String? = Strings.ManualAuditOverview.backToAudit,
            incompletePrimaryActionHelp: String,
            completePrimaryActionHelp: String,
            opensCompletionWhenComplete: Bool,
            countGroupName: @escaping (ProjectScanFile) -> String,
            detailMetrics: @escaping (Project, ProjectScanSummary, [ManualAuditDecision]) -> [Metric]
        ) {
            self.title = title
            self.subtitle = subtitle
            self.showsSpeciesBreakdown = showsSpeciesBreakdown
            self.countBreakdownTitle = countBreakdownTitle
            self.readyMetricTitle = readyMetricTitle
            self.incompletePrimaryActionTitle = incompletePrimaryActionTitle
            self.completePrimaryActionTitle = completePrimaryActionTitle
            self.secondaryActionTitle = secondaryActionTitle
            self.incompletePrimaryActionHelp = incompletePrimaryActionHelp
            self.completePrimaryActionHelp = completePrimaryActionHelp
            self.opensCompletionWhenComplete = opensCompletionWhenComplete
            self.countGroupName = countGroupName
            self.detailMetrics = detailMetrics
        }

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

    public let project: Project
    public let summary: ProjectScanSummary
    public let decisions: [ManualAuditDecision]
    public let configuration: Configuration

    /// Creates a deterministic overview snapshot from persisted scan and audit data.
    public init(
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

    public var reviewedCount: Int { decisions.count }
    public var totalCount: Int { summary.files.count }
    public var validCount: Int { decisionCount(.valid) }
    public var invalidCount: Int { decisionCount(.invalid) }
    public var remainingCount: Int { max(totalCount - reviewedCount, 0) }
    public var confirmedDetectionCount: Int { confirmedDecisions.count }
    public var isComplete: Bool { totalCount == 0 || reviewedCount == totalCount }
    public var showsSpeciesBreakdown: Bool {
        configuration.showsSpeciesBreakdown
    }
    public var countBreakdownTitle: String {
        configuration.countBreakdownTitle
    }
    public var countBreakdownRows: [CountRow] {
        groupedRows(named: configuration.countGroupName)
    }
    public var readyMetricTitle: String {
        configuration.readyMetricTitle
    }
    public var readyMetricValue: String {
        isComplete ? Strings.Common.yes : Strings.Common.notYet
    }
    public var title: String {
        configuration.title
    }
    public var subtitle: String {
        configuration.subtitle
    }
    public var primaryActionTitle: String {
        if !isComplete {
            return configuration.incompletePrimaryActionTitle
        }
        return configuration.completePrimaryActionTitle
    }
    public var primaryActionHelp: String {
        if !isComplete {
            return configuration.incompletePrimaryActionHelp
        }
        return configuration.completePrimaryActionHelp
    }
    public var secondaryActionTitle: String? {
        configuration.secondaryActionTitle
    }
    public var opensCompletionFromPrimaryAction: Bool {
        isComplete && configuration.opensCompletionWhenComplete
    }

    /// Metrics shown in the details card for the current workflow stage.
    public var detailMetrics: [Metric] {
        configuration.detailMetrics(project, summary, decisions)
    }

    /// Species counts for valid, exportable detections.
    public var speciesRows: [SpeciesRow] {
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
    public func decisionCount(_ value: ManualAuditDecisionValue) -> Int {
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

    public static func uniqueValues(_ values: [String]) -> [String] {
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
