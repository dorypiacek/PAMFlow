//
//  ManualAuditViewModel.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI

/// Preview surface requested by a manual-audit ViewModel.
enum ManualAuditPreviewKind {
    case audio
    case image
}

/// Renderable evidence row for the manual-audit side panel.
struct ManualAuditEvidenceMetric: Identifiable, Equatable {
    let title: String
    let value: String
    let valueColor: Color

    var id: String { "\(title)-\(value)" }

    init(title: String, value: String, valueColor: Color = .primary) {
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
protocol ManualAuditViewModelType: AnyObject {
    /// Loaded scan summary containing the files or detections under review.
    var summary: ProjectScanSummary? { get }
    /// Index of the currently selected file within `summary.files`.
    var selectedIndex: Int { get set }
    /// Generated audio waveform preview for the selected file.
    var preview: AudioPreview? { get }
    /// User-facing loading, preview, or persistence error.
    var errorMessage: String? { get }
    /// Indicates whether an audio preview is currently being generated.
    var isLoadingPreview: Bool { get }
    /// Currently selected scan file, if the loaded summary contains the selected index.
    var selectedFile: ProjectScanFile? { get }
    /// Human-readable position within the review queue.
    var progressText: String { get }
    /// Indicates whether the selected index can move backward.
    var canMovePrevious: Bool { get }
    /// Indicates whether the selected index can move forward.
    var canMoveNextByIndex: Bool { get }
    /// Human-readable video position for frame-based detections.
    var videoProgressText: String? { get }
    /// Indicates whether the shared evidence panel should include the generic quality row.
    func showsQualityMetric(project: Project) -> Bool

    /// Returns the screen title for the active review mode.
    func reviewTitle(project: Project) -> String
    /// Returns the preview mode for the active review queue.
    func previewKind(project: Project) -> ManualAuditPreviewKind
    /// Returns whether playback controls should be shown for the selected item.
    func showsPlaybackControls(project: Project) -> Bool
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
    /// Loads or regenerates the audio preview for the selected file.
    func loadPreview(project: Project)
    /// Persists the free-text or selected reason attached to the current decision.
    func saveInvalidReason(_ reason: String, project: Project, modelContext: ModelContext)
    /// Returns the audit reason configuration for the current module and review mode.
    func reasonConfiguration(for project: Project) -> AuditReasonConfiguration
    /// Resolves the preview image URL for frame-based detections.
    func imagePreviewURL(file: ProjectScanFile, project: Project) -> URL?
    /// Loads the preview image for frame-based detections while respecting security scope.
    func previewImage(file: ProjectScanFile, project: Project) -> NSImage?
    /// Resolves the playable media URL for modules that provide playback.
    func playbackURL(project: Project, file: ProjectScanFile) -> URL?
    /// Start offset for modules that play a clipped segment of a source file.
    func playbackStartSeconds(project: Project, file: ProjectScanFile) -> Double?
    /// Playback duration for modules that play a clipped segment of a source file.
    func playbackDurationSeconds(project: Project, file: ProjectScanFile) -> Double?
    /// Builds editable species rows for modules that support assigning species.
    func speciesAssignmentDrafts(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> [SpeciesAssignmentDraft]
}

/// View model for queue navigation, preview generation, and manual decision persistence.
@Observable
@MainActor
class ManualAuditViewModel: ManualAuditViewModelType {
    /// Loaded scan summary containing the files or detections under review.
    var summary: ProjectScanSummary?
    /// Index of the currently selected file within `summary.files`.
    var selectedIndex = 0
    /// Generated audio waveform preview for the selected file.
    var preview: AudioPreview?
    /// User-facing loading, preview, or persistence error.
    var errorMessage: String?
    /// Indicates whether an audio preview is currently being generated.
    var isLoadingPreview = false

    /// Service used to load scan summaries for audit.
    let projectScanService: ProjectScanServicing
    /// Active preview generation task for the selected file.
    private var previewTask: Task<Void, Never>?
    /// Creates a manual-audit ViewModel with an injectable scan service.
    init(projectScanService: ProjectScanServicing) {
        self.projectScanService = projectScanService
    }

    var selectedFile: ProjectScanFile? {
        guard let files = summary?.files, files.indices.contains(selectedIndex) else {
            return nil
        }

        return files[selectedIndex]
    }

    var progressText: String {
        guard let fileCount = summary?.files.count, fileCount > 0 else {
            return "No files"
        }

        return "\(selectedIndex + 1) of \(fileCount)"
    }

    var canMovePrevious: Bool {
        selectedIndex > 0
    }

    var canMoveNextByIndex: Bool {
        guard let fileCount = summary?.files.count else { return false }
        return selectedIndex < fileCount - 1
    }

    /// Position of the selected detection within the project's source videos.
    var videoProgressText: String? {
        nil
    }

    func reviewTitle(project: Project) -> String {
        Strings.ManualAudit.title
    }

    func previewKind(project: Project) -> ManualAuditPreviewKind {
        .audio
    }

    func showsPlaybackControls(project: Project) -> Bool {
        false
    }

    func decisionOptions(project: Project) -> [ManualAuditDecisionValue] {
        return [.valid, .invalid]
    }

    func shouldShowReviewAction(project: Project) -> Bool {
        false
    }

    func canAssignSpecies(project: Project) -> Bool {
        false
    }

    func canEditMaxN(project: Project) -> Bool {
        false
    }

    func showsQualityMetric(project: Project) -> Bool {
        true
    }

    func speciesTaxa(project: Project) -> [SpeciesTaxon] {
        []
    }

    func evidenceMetrics(file: ProjectScanFile, project: Project) -> [ManualAuditEvidenceMetric] {
        [
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.format, value: file.format ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.fileSize, value: formattedFileSize(file.sizeBytes))
        ]
    }

    func displaySourceName(for file: ProjectScanFile, project: Project) -> String {
        file.fileName
    }

    func qualityValueColor(_ flag: String) -> Color {
        flag.localizedCaseInsensitiveCompare("OK") == .orderedSame ? .primary : AppColors.error
    }

    func reviewHeaderText(project: Project) -> String {
        "\(project.name) - \(selectedIndex + 1)/\(summary?.files.count ?? 0)"
    }

    func fetchProject(_ projectID: UUID, modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func load(project: Project, modelContext: ModelContext, startAtLastReviewed: Bool = false) {
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

    func cancelPreviewWork() {
        previewTask?.cancel()
        previewTask = nil
        preview = nil
        isLoadingPreview = false
    }

    func loadPreview(project: Project) {
        previewTask?.cancel()
        preview = nil
        errorMessage = nil
        isLoadingPreview = false
    }

    func saveDecision(
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

    func decision(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> ManualAuditDecisionValue? {
        auditDecision(for: file, project: project, modelContext: modelContext)?.decision
    }

    func auditDecision(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> ManualAuditDecision? {
        let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func saveInvalidReason(_ reason: String, project: Project, modelContext: ModelContext) {
        guard let file = selectedFile,
              let auditDecision = auditDecision(for: file, project: project, modelContext: modelContext) else {
            return
        }
        auditDecision.notes = reason
        auditDecision.updatedAt = .now
        try? modelContext.save()
    }

    func reasonConfiguration(for project: Project) -> AuditReasonConfiguration {
        return .freeTextOptional()
    }

    func decision(
        for file: ProjectScanFile,
        project: Project,
        modelContext: ModelContext,
        version: Int
    ) -> ManualAuditDecisionValue? {
        _ = version
        return decision(for: file, project: project, modelContext: modelContext)
    }

    func speciesSelection(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> SpeciesSelection {
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

    func speciesSelections(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> [SpeciesSelection] {
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

    func isRemovedFromExport(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> Bool {
        auditDecision(for: file, project: project, modelContext: modelContext)?.isRemovedFromExport == true
    }

    func effectiveMaxN(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> Int? {
        auditDecision(for: file, project: project, modelContext: modelContext)?.userMaxN
    }

    func saveSpeciesSelection(
        _ selection: SpeciesSelection,
        project: Project,
        modelContext: ModelContext
    ) throws {
        try saveSpeciesSelection(selection, replacingID: selection.id, project: project, modelContext: modelContext)
    }

    func saveSpeciesSelection(
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

    func deleteSpeciesSelection(
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
    func replaceSpeciesSelection(
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
    func clearSpeciesSelections(project: Project, modelContext: ModelContext) throws {
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
    func saveSpeciesAssignment(
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

    func setRemovedFromExport(
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

    func saveMaxNOverride(
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

    func playbackURL(project: Project, file: ProjectScanFile) -> URL? {
        nil
    }

    func imagePreviewURL(file: ProjectScanFile, project: Project) -> URL? {
        nil
    }

    func previewImage(file: ProjectScanFile, project: Project) -> NSImage? {
        guard let previewURL = imagePreviewURL(file: file, project: project) else {
            return nil
        }

        let scopedURL = previewURL.path.hasPrefix(project.rootFolderURL?.path ?? "")
            ? project.rootFolderURL
            : project.inputFolderURL
        let accessed = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessed {
                scopedURL?.stopAccessingSecurityScopedResource()
            }
        }

        return NSImage(contentsOf: previewURL)
    }

    func playbackStartSeconds(project: Project, file: ProjectScanFile) -> Double? {
        nil
    }

    func playbackDurationSeconds(project: Project, file: ProjectScanFile) -> Double? {
        nil
    }

    func movePrevious(project: Project) {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
        loadPreview(project: project)
    }

    func moveNext(project: Project) {
        guard let fileCount = summary?.files.count, selectedIndex < fileCount - 1 else { return }
        selectedIndex += 1
        AppLog.info("Manual audit moved to next index \(selectedIndex)")
        loadPreview(project: project)
    }

    func completedCount(project: Project, modelContext: ModelContext) -> Int {
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

    func formatDuration(_ seconds: Double) -> String {
        seconds >= 60 ? "\(Int(seconds.rounded())) seconds" : String(format: "%.1f seconds", seconds)
    }

    func formattedFileSize(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    func speciesAssignmentDrafts(
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

    func workflowStatusAfterSavingDecision(
        reviewedCount: Int,
        totalCount: Int,
        project: Project
    ) -> ProjectWorkflowStatus {
        reviewedCount >= totalCount ? .completed : .inProgress
    }

    func sortFiles(_ files: inout [ProjectScanFile], project: Project) {
        files.sort { suspicionScore($0) > suspicionScore($1) }
    }
}
