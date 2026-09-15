//
//  BRUVProjectCompletionViewModel.swift
//  PAMFlow
//
//  Created by Dory on 14/09/2026.
//

import Core
import Foundation
import Observation
import SwiftData
import UI

/// ViewModel for completing BRUV and RUV workflows.
@Observable
@MainActor
final class BRUVProjectCompletionViewModel: ProjectCompletionViewModel {
    override var configuration: ProjectCompletionConfiguration {
        ProjectCompletionConfiguration(
            title: BRUVStrings.Completion.title,
            subtitle: BRUVStrings.Completion.subtitle,
            overviewTitle: BRUVStrings.Completion.projectOverview,
            projectTitle: BRUVStrings.Completion.project,
            processedByTitle: BRUVStrings.Completion.processedBy,
            reviewedFilesTitle: BRUVStrings.Completion.reviewedFiles,
            validDecisionsTitle: BRUVStrings.Completion.validDecisions,
            unsureDecisionsTitle: BRUVStrings.Completion.unsureDecisions,
            invalidDecisionsTitle: BRUVStrings.Completion.invalidDecisions,
            completeButtonTitle: BRUVStrings.Completion.complete,
            backToProjectsButtonTitle: BRUVStrings.Completion.backToProjects,
            exportButtonTitle: BRUVStrings.Completion.exportDetections
        )
    }

    override var availableExportFields: [ProjectCompletionExportField] {
        BRUVExportField.allCases.map(\.descriptor)
    }

    override func metrics(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        appCoordinator: AppCoordinating
    ) -> [ProjectCompletionMetric] {
        var metrics = super.metrics(project: project, summary: summary, decisions: decisions, appCoordinator: appCoordinator)
        metrics.append(contentsOf: [
            ProjectCompletionMetric(title: Strings.ExportFields.frameCount, value: frameCountRange(summary)),
            ProjectCompletionMetric(title: "Resolutions", value: summary.resolutions?.joined(separator: ", ") ?? Strings.Common.unknown),
            ProjectCompletionMetric(title: "Source videos", value: "\(Set(summary.files.compactMap(\.sourceVideo)).count)")
        ])
        return metrics
    }

    override func export(
        project: Project,
        decisions: [ManualAuditDecision],
        fields: [ProjectCompletionExportField],
        modelContext: ModelContext,
        appCoordinator: AppCoordinating
    ) {
        guard let summary else { return }
        guard let url = appCoordinator.dependencies.fileSelectionService.selectSaveDestination(
            defaultName: "\(project.name)_detections.csv",
            canCreateDirectories: true
        ) else { return }

        do {
            let selectedFields = fields.compactMap { BRUVExportField(rawValue: $0.id) }
            let csv = BRUVDetectionCSV(
                project: project,
                summary: summary,
                decisions: decisions,
                fields: selectedFields,
                processedBy: processedBy(for: project, appCoordinator: appCoordinator)
            ).string
            try csv.write(to: url, atomically: true, encoding: .utf8)
            markExported(
                url: url,
                project: project,
                modelContext: modelContext,
                appCoordinator: appCoordinator,
                message: String(format: BRUVStrings.Completion.exportSuccessFormat, url.lastPathComponent)
            )
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    private func frameCountRange(_ summary: ProjectScanSummary) -> String {
        guard let minimum = summary.frameCountMin, let maximum = summary.frameCountMax else {
            return Strings.Common.unknown
        }
        return minimum == maximum ? "\(minimum)" : "\(minimum)-\(maximum)"
    }
}

private enum BRUVExportField: String, CaseIterable {
    case project
    case opcode
    case date
    case location
    case depth
    case bottomType
    case waterTemperature
    case fileName
    case relativePath
    case sourceMedia
    case frameNumber
    case trackID
    case maxN
    case confidence
    case decision
    case reason
    case speciesFamily
    case speciesGenus
    case speciesName
    case speciesFullName
    case width
    case height
    case frameRate
    case frameCount
    case format
    case sizeBytes
    case processedBy

    var descriptor: ProjectCompletionExportField {
        ProjectCompletionExportField(id: rawValue, title: title, isRequired: self == .project || self == .fileName)
    }

    var title: String {
        switch self {
        case .project: return Strings.ProjectCompletion.project
        case .opcode: return Strings.ExportFields.opcode
        case .date: return Strings.ProjectCompletion.date
        case .location: return Strings.ExportFields.location
        case .depth: return Strings.ExportFields.depth
        case .bottomType: return Strings.ExportFields.bottomType
        case .waterTemperature: return Strings.ExportFields.waterTemperature
        case .fileName: return Strings.ExportFields.fileName
        case .relativePath: return Strings.ExportFields.relativePath
        case .sourceMedia: return Strings.ExportFields.sourceMedia
        case .frameNumber: return Strings.ExportFields.frameNumber
        case .trackID: return Strings.ExportFields.trackID
        case .maxN: return Strings.ExportFields.maxN
        case .confidence: return Strings.ExportFields.confidence
        case .decision: return Strings.ExportFields.decision
        case .reason: return Strings.ExportFields.reason
        case .speciesFamily: return Strings.ExportFields.speciesFamily
        case .speciesGenus: return Strings.ExportFields.speciesGenus
        case .speciesName: return Strings.ExportFields.speciesName
        case .speciesFullName: return Strings.ExportFields.speciesFullName
        case .width: return Strings.ExportFields.width
        case .height: return Strings.ExportFields.height
        case .frameRate: return Strings.ExportFields.frameRate
        case .frameCount: return Strings.ExportFields.frameCount
        case .format: return Strings.ExportFields.format
        case .sizeBytes: return Strings.ExportFields.sizeBytes
        case .processedBy: return Strings.ExportFields.processedBy
        }
    }
}

private struct BRUVDetectionCSV {
    let project: Project
    let summary: ProjectScanSummary
    let decisions: [ManualAuditDecision]
    let fields: [BRUVExportField]
    let processedBy: String

    var string: String {
        let header = fields.map(\.title).map(Self.escape).joined(separator: ",")
        let rows = summary.files.map { file in
            fields
                .map { Self.escape(value(for: $0, file: file, decision: decision(for: file))) }
                .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private func decision(for file: ProjectScanFile) -> ManualAuditDecision? {
        decisions
            .filter { $0.fileRelativePath == file.relativePath }
            .sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
            .first
    }

    private func value(for field: BRUVExportField, file: ProjectScanFile, decision: ManualAuditDecision?) -> String {
        switch field {
        case .project: project.name
        case .opcode: project.metadataValue(for: BRUVMetadataFieldID.opcode) ?? ""
        case .date: project.metadataValue(for: BRUVMetadataFieldID.date) ?? ""
        case .location: project.metadataValue(for: BRUVMetadataFieldID.location) ?? ""
        case .depth: project.metadataValue(for: BRUVMetadataFieldID.depth) ?? ""
        case .bottomType: project.metadataValue(for: BRUVMetadataFieldID.bottomType) ?? ""
        case .waterTemperature: project.metadataValue(for: BRUVMetadataFieldID.waterTemperature) ?? ""
        case .fileName: file.fileName
        case .relativePath: file.relativePath
        case .sourceMedia: file.sourceVideo ?? ""
        case .frameNumber: file.frameNumber.map(String.init) ?? ""
        case .trackID: file.trackID.map(String.init) ?? ""
        case .maxN: file.maxN.map(String.init) ?? ""
        case .confidence: file.sharkTrackConfidence.map { String(format: "%.4f", $0) } ?? ""
        case .decision: decision?.decision.rawValue ?? ""
        case .reason: decision?.notes ?? ""
        case .speciesFamily: decision?.speciesFamily ?? ""
        case .speciesGenus: decision?.speciesGenus ?? ""
        case .speciesName: decision?.speciesName ?? ""
        case .speciesFullName: decision?.speciesFullName ?? ""
        case .width: file.width.map(String.init) ?? ""
        case .height: file.height.map(String.init) ?? ""
        case .frameRate: file.frameRate.map { String(format: "%.3f", $0) } ?? ""
        case .frameCount: file.frameCount.map(String.init) ?? ""
        case .format: file.format ?? ""
        case .sizeBytes: "\(file.sizeBytes)"
        case .processedBy: processedBy
        }
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
