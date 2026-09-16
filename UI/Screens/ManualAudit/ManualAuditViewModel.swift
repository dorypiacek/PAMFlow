//
//  ManualAuditViewModel.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import AppKit
import Core
import Foundation
import Observation
import SwiftData
import SwiftUI

/// Renderable evidence row for the manual-audit side panel.
public struct ManualAuditEvidenceMetric: Identifiable, Equatable {
    public let title: String
    public let value: String
    public let valueColor: Color

    public var id: String { "\(title)-\(value)" }

    public init(title: String, value: String, valueColor: Color = .primary) {
        self.title = title
        self.value = value
        self.valueColor = valueColor
    }
}

/// Defines state and actions for manual audit.
///
/// The ViewModel loads scan evidence, tracks the selected file, manages preview
/// generation, and persists human decisions.
@MainActor
public protocol ManualAuditViewModelType: AnyObject {
    /// Loaded scan summary containing the files or detections under review.
    var summary: ProjectScanSummary? { get }
    /// Index of the currently selected file within `summary.files`.
    var selectedIndex: Int { get set }
    /// User-facing loading, preview, or persistence error.
    var errorMessage: String? { get }
    /// Indicates whether module-specific preview evidence is currently loading.
    var isLoadingPreview: Bool { get }
    /// Currently selected scan file, if the loaded summary contains the selected index.
    var selectedFile: ProjectScanFile? { get }
    /// Human-readable position within the review queue.
    var progressText: String { get }
    /// Indicates whether the selected index can move backward.
    var canMovePrevious: Bool { get }
    /// Indicates whether the selected index can move forward.
    var canMoveNextByIndex: Bool { get }
    /// Indicates whether the shared evidence panel should include the generic quality row.
    func showsQualityMetric(project: Project) -> Bool
    /// Indicates whether the shared evidence panel should include the generic file-name row.
    func showsFileNameMetric(project: Project) -> Bool

    /// Returns the screen title for the active review mode.
    func reviewTitle(project: Project) -> String
    /// Returns the decisions available for the active review mode.
    func decisionOptions(project: Project) -> [ManualAuditDecisionValue]
    /// Returns whether an additional action button should be shown for a decision.
    func shouldShowReviewAction(project: Project) -> Bool
    /// Returns whether valid decisions can assign species.
    func canAssignSpecies(project: Project) -> Bool
    /// Returns whether MaxN can be edited for the selected file.
    func canEditMaxN(project: Project) -> Bool
    /// Returns taxa available for species assignment in the current review mode.
    func speciesTaxa(project: Project) -> [SpeciesTaxon]
    /// Builds evidence rows for the selected scan file.
    func evidenceMetrics(file: ProjectScanFile, project: Project) -> [ManualAuditEvidenceMetric]
    /// Returns the display name for the reviewed source item.
    func displaySourceName(for file: ProjectScanFile, project: Project) -> String
    /// Builds the title text for the current review mode.
    func reviewHeaderText(project: Project) -> String
    /// Fetches the project associated with the manual-audit screen.
    func fetchProject(_ projectID: UUID, modelContext: ModelContext) -> Project?
    /// Loads scan evidence, sorts it for review, selects the initial file, and starts preview work.
    func load(project: Project, modelContext: ModelContext, startAtLastReviewed: Bool)
    /// Cancels preview generation and clears preview cache state owned by this screen.
    func cancelPreviewWork()
    /// Lets modules load or regenerate preview evidence for the selected file.
    func loadPreview(project: Project)
    /// Persists the free-text or selected reason attached to the current decision.
    func saveInvalidReason(_ reason: String, project: Project, modelContext: ModelContext)
    /// Returns the audit reason configuration for the current module and review mode.
    func reasonConfiguration(for project: Project) -> AuditReasonConfiguration
    /// Builds editable species rows for modules that support assigning species.
    func speciesAssignmentDrafts(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> [SpeciesAssignmentDraft]
}

/// View model for queue navigation, preview generation, and manual decision persistence.
@Observable
@MainActor
open class ManualAuditViewModel: ManualAuditViewModelType {
    /// Loaded scan summary containing the files or detections under review.
    public var summary: ProjectScanSummary?
    /// Index of the currently selected file within `summary.files`.
    public var selectedIndex = 0
    /// User-facing loading, preview, or persistence error.
    public var errorMessage: String?
    /// Indicates whether module-specific preview evidence is currently loading.
    public var isLoadingPreview = false

    /// Service used to load scan summaries for audit.
    public let projectScanService: ProjectScanServicing
    /// Active preview generation task for the selected file.
    private var previewTask: Task<Void, Never>?
    /// Creates a manual-audit ViewModel with an injectable scan service.
    public init(projectScanService: ProjectScanServicing) {
        self.projectScanService = projectScanService
    }

    public var selectedFile: ProjectScanFile? {
        guard let files = summary?.files, files.indices.contains(selectedIndex) else {
            return nil
        }

        return files[selectedIndex]
    }

    public var progressText: String {
        guard let fileCount = summary?.files.count, fileCount > 0 else {
            return "No files"
        }

        return "\(selectedIndex + 1) of \(fileCount)"
    }

    public var canMovePrevious: Bool {
        selectedIndex > 0
    }

    public var canMoveNextByIndex: Bool {
        guard let fileCount = summary?.files.count else { return false }
        return selectedIndex < fileCount - 1
    }

    open func reviewTitle(project: Project) -> String {
        Strings.ManualAudit.title
    }

    open func decisionOptions(project: Project) -> [ManualAuditDecisionValue] {
        return [.valid, .invalid]
    }

    open func shouldShowReviewAction(project: Project) -> Bool {
        false
    }

    open func canAssignSpecies(project: Project) -> Bool {
        false
    }

    open func canEditMaxN(project: Project) -> Bool {
        false
    }

    open func showsQualityMetric(project: Project) -> Bool {
        true
    }

    open func showsFileNameMetric(project: Project) -> Bool {
        true
    }

    open func speciesTaxa(project: Project) -> [SpeciesTaxon] {
        []
    }

    open func evidenceMetrics(file: ProjectScanFile, project: Project) -> [ManualAuditEvidenceMetric] {
        [
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.format, value: file.format ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.fileSize, value: formattedFileSize(file.sizeBytes))
        ]
    }

    open func displaySourceName(for file: ProjectScanFile, project: Project) -> String {
        file.fileName
    }

    open func qualityValueColor(_ flag: String) -> Color {
        flag.localizedCaseInsensitiveCompare("OK") == .orderedSame ? .primary : AppColors.error
    }

    open func reviewHeaderText(project: Project) -> String {
        "\(project.name) - \(selectedIndex + 1)/\(summary?.files.count ?? 0)"
    }

    public func fetchProject(_ projectID: UUID, modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    open func load(project: Project, modelContext: ModelContext, startAtLastReviewed: Bool = false) {
        do {
            AppLog.info("Manual audit loading project '\(project.name)'")
            var loadedSummary = try projectScanService.loadSummary(for: project)
            sortFiles(&loadedSummary.files, project: project)
            summary = loadedSummary
            selectedIndex = startAtLastReviewed
                ? lastReviewedIndex(project: project, modelContext: modelContext)
                : firstUndecidedIndex(project: project, modelContext: modelContext)
            AppLog.info("Manual audit loaded \(loadedSummary.files.count) files; selected index \(selectedIndex)")
            errorMessage = nil
            loadPreview(project: project)
        } catch {
            AppLog.info("Manual audit load failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    open func cancelPreviewWork() {
        previewTask?.cancel()
        previewTask = nil
        isLoadingPreview = false
    }

    open func loadPreview(project: Project) {
        previewTask?.cancel()
        errorMessage = nil
        isLoadingPreview = false
    }

    public func saveDecision(
        _ value: ManualAuditDecisionValue,
        project: Project,
        modelContext: ModelContext
    ) throws {
        guard let file = selectedFile else { return }
        AppLog.info("Manual audit saving decision \(value.rawValue) for \(file.relativePath)")

        let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.id == id
            }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.decision = value
        } else {
            modelContext.insert(
                ManualAuditDecision(
                    projectID: project.id,
                    fileRelativePath: file.relativePath,
                    decision: value
                )
            )
        }

        let reviewedCount = completedCount(project: project, modelContext: modelContext)
        project.workflowStatus = workflowStatusAfterSavingDecision(
            reviewedCount: reviewedCount,
            totalCount: summary?.files.count ?? 0,
            project: project
        )
        project.lastOpenedAt = .now
        try modelContext.save()
        AppLog.info("Manual audit saved decision; status=\(project.workflowStatus.rawValue)")
    }

    public func decision(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> ManualAuditDecisionValue? {
        auditDecision(for: file, project: project, modelContext: modelContext)?.decision
    }

    public func auditDecision(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> ManualAuditDecision? {
        let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    public func saveInvalidReason(_ reason: String, project: Project, modelContext: ModelContext) {
        guard let file = selectedFile,
              let auditDecision = auditDecision(for: file, project: project, modelContext: modelContext) else {
            return
        }
        auditDecision.notes = reason
        auditDecision.updatedAt = .now
        try? modelContext.save()
    }

    open func reasonConfiguration(for project: Project) -> AuditReasonConfiguration {
        return .freeTextOptional()
    }

    public func decision(
        for file: ProjectScanFile,
        project: Project,
        modelContext: ModelContext,
        version: Int
    ) -> ManualAuditDecisionValue? {
        _ = version
        return decision(for: file, project: project, modelContext: modelContext)
    }

    public func speciesSelection(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> SpeciesSelection {
        guard let decision = auditDecision(for: file, project: project, modelContext: modelContext) else {
            return SpeciesSelection(family: nil, genus: nil, species: nil, fullName: "")
        }

        return SpeciesSelection(
            family: decision.speciesFamily,
            genus: decision.speciesGenus,
            species: decision.speciesName,
            fullName: decision.speciesFullName ?? ""
        )
    }

    public func speciesSelections(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> [SpeciesSelection] {
        guard let decision = auditDecision(for: file, project: project, modelContext: modelContext) else {
            return []
        }

        if let data = decision.speciesSelectionsJSON?.data(using: .utf8),
           let selections = try? JSONDecoder().decode([SpeciesSelection].self, from: data) {
            return selections
        }

        let legacySelection = SpeciesSelection(
            family: decision.speciesFamily,
            genus: decision.speciesGenus,
            species: decision.speciesName,
            fullName: decision.speciesFullName ?? ""
        )
        return legacySelection.fullName.isEmpty ? [] : [legacySelection]
    }

    public func isRemovedFromExport(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> Bool {
        auditDecision(for: file, project: project, modelContext: modelContext)?.isRemovedFromExport == true
    }

    open func effectiveMaxN(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> Int? {
        auditDecision(for: file, project: project, modelContext: modelContext)?.userMaxN
    }

    public func saveSpeciesSelection(
        _ selection: SpeciesSelection,
        project: Project,
        modelContext: ModelContext
    ) throws {
        try saveSpeciesSelection(selection, replacingID: selection.id, project: project, modelContext: modelContext)
    }

    public func saveSpeciesSelection(
        _ selection: SpeciesSelection,
        replacingID selectionID: String?,
        project: Project,
        modelContext: ModelContext
    ) throws {
        guard let file = selectedFile else { return }
        let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.id == id
            }
        )

        let decision: ManualAuditDecision
        if let existing = try modelContext.fetch(descriptor).first {
            decision = existing
        } else {
            decision = ManualAuditDecision(
                projectID: project.id,
                fileRelativePath: file.relativePath,
                decision: .unsure
            )
            modelContext.insert(decision)
        }

        var selections = speciesSelections(for: file, project: project, modelContext: modelContext)
        let normalizedSelection = SpeciesSelection(
            id: selectionID ?? selection.id,
            family: selection.family,
            genus: selection.genus,
            species: selection.species,
            fullName: selection.fullName
        )
        if let index = selections.firstIndex(where: { $0.id == normalizedSelection.id }) {
            selections[index] = normalizedSelection
        } else {
            selections.append(normalizedSelection)
        }

        decision.speciesFamily = selections.first?.family
        decision.speciesGenus = selections.first?.genus
        decision.speciesName = selections.first?.species
        decision.speciesFullName = selections.first?.fullName.isEmpty == false ? selections.first?.fullName : nil
        decision.speciesSelectionsJSON = try String(
            data: JSONEncoder().encode(selections),
            encoding: .utf8
        )
        decision.updatedAt = .now
        try modelContext.save()
    }

    public func deleteSpeciesSelection(
        _ selection: SpeciesSelection,
        project: Project,
        modelContext: ModelContext
    ) throws {
        guard let file = selectedFile,
              let decision = auditDecision(for: file, project: project, modelContext: modelContext) else { return }

        let selections = speciesSelections(for: file, project: project, modelContext: modelContext)
            .filter { $0.id != selection.id }
        decision.speciesSelectionsJSON = try String(data: JSONEncoder().encode(selections), encoding: .utf8)
        decision.speciesFamily = selections.first?.family
        decision.speciesGenus = selections.first?.genus
        decision.speciesName = selections.first?.species
        decision.speciesFullName = selections.first?.fullName.isEmpty == false ? selections.first?.fullName : nil
        decision.updatedAt = .now
        try modelContext.save()
    }

    /// Replaces any legacy multi-species value with one species for this track.
    public func replaceSpeciesSelection(
        _ selection: SpeciesSelection,
        project: Project,
        modelContext: ModelContext
    ) throws {
        guard let file = selectedFile else { return }
        try clearSpeciesSelections(project: project, modelContext: modelContext)
        try saveSpeciesSelection(
            selection,
            replacingID: selection.id,
            project: project,
            modelContext: modelContext
        )
        AppLog.info("Saved species for \(file.relativePath)")
    }

    /// Clears species metadata while retaining the human review decision.
    public func clearSpeciesSelections(project: Project, modelContext: ModelContext) throws {
        guard let file = selectedFile,
              let decision = auditDecision(for: file, project: project, modelContext: modelContext) else { return }
        decision.speciesFamily = nil
        decision.speciesGenus = nil
        decision.speciesName = nil
        decision.speciesFullName = nil
        decision.speciesSelectionsJSON = nil
        decision.updatedAt = .now
        try modelContext.save()
    }

    /// Persists one modal row against its own detection record.
    public func saveSpeciesAssignment(
        _ draft: SpeciesAssignmentDraft,
        project: Project,
        modelContext: ModelContext
    ) throws {
        guard let file = summary?.files.first(where: { $0.relativePath == draft.id }) else { return }
        let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in decision.id == id }
        )
        let decision: ManualAuditDecision
        if let existing = try modelContext.fetch(descriptor).first {
            decision = existing
        } else {
            decision = ManualAuditDecision(
                projectID: project.id,
                fileRelativePath: file.relativePath,
                decision: .valid
            )
            modelContext.insert(decision)
        }
        decision.isRemovedFromExport = draft.isRemoved
        decision.speciesFamily = draft.selection?.family
        decision.speciesGenus = draft.selection?.genus
        decision.speciesName = draft.selection?.species
        decision.speciesFullName = draft.selection?.fullName
        decision.speciesSelectionsJSON = try draft.selection.map {
            try String(data: JSONEncoder().encode([$0]), encoding: .utf8)
        } ?? nil
        decision.updatedAt = .now
        try modelContext.save()
    }

    public func setRemovedFromExport(
        _ isRemoved: Bool,
        project: Project,
        modelContext: ModelContext
    ) throws {
        guard let file = selectedFile else { return }
        let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.id == id
            }
        )

        let decision: ManualAuditDecision
        if let existing = try modelContext.fetch(descriptor).first {
            decision = existing
        } else {
            decision = ManualAuditDecision(projectID: project.id, fileRelativePath: file.relativePath, decision: .invalid)
            modelContext.insert(decision)
        }

        decision.isRemovedFromExport = isRemoved
        decision.updatedAt = .now
        try modelContext.save()
    }

    public func saveMaxNOverride(
        _ maxN: Int?,
        project: Project,
        modelContext: ModelContext
    ) throws {
        guard let file = selectedFile else { return }
        let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.id == id
            }
        )

        guard let decision = try modelContext.fetch(descriptor).first else { return }

        decision.userMaxN = maxN
        decision.updatedAt = .now
        try modelContext.save()
    }

    public func movePrevious(project: Project) {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
        loadPreview(project: project)
    }

    public func moveNext(project: Project) {
        guard let fileCount = summary?.files.count, selectedIndex < fileCount - 1 else { return }
        selectedIndex += 1
        AppLog.info("Manual audit moved to next index \(selectedIndex)")
        loadPreview(project: project)
    }

    public func completedCount(project: Project, modelContext: ModelContext) -> Int {
        let projectID = project.id
        let summaryFilePaths = Set(summary?.files.map(\.relativePath) ?? [])
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        let decisions = (try? modelContext.fetch(descriptor)) ?? []
        let paths = Set(decisions.map(\.fileRelativePath).filter {
            summaryFilePaths.isEmpty || summaryFilePaths.contains($0)
        })
        return paths.count
    }

    private func firstUndecidedIndex(project: Project, modelContext: ModelContext) -> Int {
        guard let files = summary?.files else { return 0 }

        for index in files.indices {
            if decision(for: files[index], project: project, modelContext: modelContext) == nil {
                return index
            }
        }

        return 0
    }

    private func lastReviewedIndex(project: Project, modelContext: ModelContext) -> Int {
        guard let files = summary?.files else { return 0 }

        for index in files.indices.reversed() {
            if decision(for: files[index], project: project, modelContext: modelContext) != nil {
                return index
            }
        }

        return firstUndecidedIndex(project: project, modelContext: modelContext)
    }

    private func suspicionScore(_ file: ProjectScanFile) -> Double {
        var score = 0.0

        if !file.readable { score += 1_000 }
        if file.qualityFlag.lowercased() != "ok" { score += 100 }
        score += Double(file.qualityReasons.count) * 25
        if file.durationSeconds == nil {
            score += 30
        }

        return score
    }

    public func formatDuration(_ seconds: Double) -> String {
        seconds >= 60 ? "\(Int(seconds.rounded())) seconds" : String(format: "%.1f seconds", seconds)
    }

    public func formattedFileSize(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    open func speciesAssignmentDrafts(
        for file: ProjectScanFile,
        project: Project,
        modelContext: ModelContext
    ) -> [SpeciesAssignmentDraft] {
        [
            SpeciesAssignmentDraft(
                id: file.relativePath,
                primaryLabel: file.fileName,
                secondaryLabel: Strings.Common.unknown,
                selection: speciesSelections(for: file, project: project, modelContext: modelContext).first,
                isRemoved: isRemovedFromExport(for: file, project: project, modelContext: modelContext)
            )
        ]
    }

    open func workflowStatusAfterSavingDecision(
        reviewedCount: Int,
        totalCount: Int,
        project: Project
    ) -> ProjectWorkflowStatus {
        reviewedCount >= totalCount ? .completed : .inProgress
    }

    open func sortFiles(_ files: inout [ProjectScanFile], project: Project) {
        files.sort { suspicionScore($0) > suspicionScore($1) }
    }
}
