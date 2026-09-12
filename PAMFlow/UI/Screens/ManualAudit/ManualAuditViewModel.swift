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

    /// Builds the title text for the current review mode.
    func reviewHeaderText(projectName: String, module: WorkflowModule) -> String
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
    func sharkTrackPreviewURL(file: ProjectScanFile, project: Project) -> URL?
    /// Loads the preview image for frame-based detections while respecting security scope.
    func sharkTrackImage(file: ProjectScanFile, project: Project) -> NSImage?
}

/// View model for queue navigation, preview generation, and manual decision persistence.
@Observable
@MainActor
final class ManualAuditViewModel: ManualAuditViewModelType {
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
    private let projectScanService: ProjectScanServicing
    /// Service used to generate, cache, and preheat audio previews.
    private let audioPreviewCacheService: AudioPreviewCacheServicing
    /// Active preview generation task for the selected file.
    private var previewTask: Task<Void, Never>?
    /// Preview preheating tasks keyed by media path and clip range.
    private var prewarmTasks: [String: Task<Void, Never>] = [:]
    /// Number of upcoming previews to warm after the selected file.
    private let prewarmCount = Metrics.Cache.manualAuditPrewarmCount

    /// Creates a manual-audit ViewModel with injectable scan and audio-preview services.
    init(projectScanService: ProjectScanServicing, audioPreviewCacheService: AudioPreviewCacheServicing) {
        self.projectScanService = projectScanService
        self.audioPreviewCacheService = audioPreviewCacheService
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
        guard let files = summary?.files,
              let sourceVideo = selectedFile?.sourceVideo else { return nil }
        var videos: [String] = []
        for video in files.compactMap(\.sourceVideo) where !videos.contains(video) {
            videos.append(video)
        }
        guard let index = videos.firstIndex(of: sourceVideo) else { return nil }
        return "Processing video \(index + 1)/\(videos.count)"
    }

    func reviewHeaderText(projectName: String, module: WorkflowModule) -> String {
        if module == .pamAudio {
            let format = summary?.files.contains(where: { $0.sharkTrackStatus == ProjectScanStatus.pamguard }) == true
                ? Strings.ManualAudit.detectionProgressFormat
                : Strings.ManualAudit.sampleProgressFormat
            return "\(projectName) - \(String(format: format, selectedIndex + 1, summary?.files.count ?? 0))"
        }

        guard let files = summary?.files,
              let selectedFile,
              let sourceVideo = selectedFile.sourceVideo else {
            return "\(projectName) - Detection \(selectedIndex + 1)/\(summary?.files.count ?? 0)"
        }
        var videos: [String] = []
        for video in files.compactMap(\.sourceVideo) where !videos.contains(video) {
            videos.append(video)
        }
        let videoIndex = (videos.firstIndex(of: sourceVideo) ?? 0) + 1
        let videoFiles = files.filter { $0.sourceVideo == sourceVideo }
        let detectionIndex = (videoFiles.firstIndex(where: { $0.relativePath == selectedFile.relativePath }) ?? 0) + 1
        return "\(projectName) - Video \(videoIndex)/\(videos.count) - Detection \(detectionIndex)/\(videoFiles.count)"
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
            if loadedSummary.files.contains(where: { $0.sharkTrackStatus == ProjectScanStatus.pamguard }) {
                loadedSummary.files.sort {
                    ($0.trackID ?? Int.max) < ($1.trackID ?? Int.max)
                }
            } else if WorkflowModule.module(for: project.moduleID).requiresSharkTrack {
                loadedSummary.files.sort {
                    let videoOrder = ($0.sourceVideo ?? "")
                        .localizedStandardCompare($1.sourceVideo ?? "")
                    if videoOrder != .orderedSame {
                        return videoOrder == .orderedAscending
                    }
                    let leftTrack = $0.trackID ?? Int.max
                    let rightTrack = $1.trackID ?? Int.max
                    if leftTrack == rightTrack {
                        return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                    }
                    return leftTrack < rightTrack
                }
            } else {
                loadedSummary.files.sort { suspicionScore($0) > suspicionScore($1) }
            }
            summary = loadedSummary
            selectedIndex = startAtLastReviewed
                ? lastReviewedIndex(project: project, modelContext: modelContext)
                : firstUndecidedIndex(project: project, modelContext: modelContext)
            AppLog.info("Manual audit loaded \(loadedSummary.files.count) files; selected index \(selectedIndex)")
            errorMessage = nil
            loadPreview(project: project)
            prewarmNearbyPreviews(project: project)
        } catch {
            AppLog.info("Manual audit load failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func cancelPreviewWork() {
        previewTask?.cancel()
        previewTask = nil
        for task in prewarmTasks.values {
            task.cancel()
        }
        prewarmTasks.removeAll(keepingCapacity: false)
        preview = nil
        isLoadingPreview = false
        audioPreviewCacheService.clear()
    }

    func loadPreview(project: Project) {
        AppLog.info("Manual audit loading preview for index \(selectedIndex)")
        previewTask?.cancel()
        preview = nil
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio else {
            AppLog.info("Manual audit preview uses SharkTrack image for non-audio project")
            errorMessage = nil
            isLoadingPreview = false
            return
        }

        guard let file = selectedFile,
              let inputFolderURL = project.inputFolderURL else {
            AppLog.info("Manual audit preview skipped: selectedFile or input folder unavailable")
            isLoadingPreview = false
            return
        }

        guard let url = audioURL(project: project, file: file) else {
            AppLog.info("Manual audit preview skipped for non-audio source \(file.sourceVideo ?? file.relativePath)")
            errorMessage = nil
            isLoadingPreview = false
            prewarmNearbyPreviews(project: project)
            return
        }
        let clipStart = clipStartSeconds(project: project, file: file)
        let clipDuration = clipDurationSeconds(project: project, file: file)
        if let cachedPreview = audioPreviewCacheService.cachedPreview(
            for: url,
            clipStartSeconds: clipStart,
            clipDurationSeconds: clipDuration
        ) {
            AppLog.info("Manual audit preview cache hit for \(file.relativePath)")
            preview = cachedPreview
            errorMessage = nil
            isLoadingPreview = false
            prewarmNearbyPreviews(project: project)
            return
        }

        AppLog.info("Manual audit preview starting for \(file.relativePath)")
        isLoadingPreview = true

        previewTask = Task { [inputFolderURL, url, relativePath = file.relativePath, clipStart, clipDuration] in
            do {
                let preview = try await audioPreviewCacheService.preview(
                    from: url,
                    securityScopedURL: inputFolderURL,
                    clipStartSeconds: clipStart,
                    clipDurationSeconds: clipDuration
                )

                guard !Task.isCancelled,
                      self.selectedFile?.relativePath == relativePath else {
                    return
                }

                self.preview = preview
                self.errorMessage = nil
                AppLog.info("Manual audit preview loaded for \(relativePath)")
                self.prewarmNearbyPreviews(project: project)
            } catch {
                guard !Task.isCancelled,
                      self.selectedFile?.relativePath == relativePath else {
                    return
                }

                self.preview = nil
                self.errorMessage = error.localizedDescription
                AppLog.info("Manual audit preview failed for \(relativePath): \(error.localizedDescription)")
            }
            self.isLoadingPreview = false
        }
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
        if isPAMGuardDetectionReview(project: project) {
            project.workflowStatus = reviewedCount >= (summary?.files.count ?? 0) ? .completed : .detectionReviewInProgress
        } else {
            project.workflowStatus = reviewedCount >= (summary?.files.count ?? 0) ? .manualAuditCompleted : .manualAuditInProgress
        }
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
        let module = WorkflowModule.module(for: project.moduleID)
        if module == .pamAudio {
            return isPAMGuardDetectionReview(project: project)
                ? .pamDetectionReview()
                : .manualAudit()
        }

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
        auditDecision(for: file, project: project, modelContext: modelContext)?.userMaxN ?? file.maxN
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
        AppLog.info("Saved species for track \(file.trackID.map(String.init) ?? "unknown")")
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

    /// Returns every SharkTrack individual represented on the selected frame.
    func detectionsInCurrentFrame(for file: ProjectScanFile) -> [ProjectScanFile] {
        guard let files = summary?.files,
              let frameNumber = file.frameNumber else { return [file] }
        let matches = files.filter {
            $0.sourceVideo == file.sourceVideo &&
            $0.frameNumber == frameNumber
        }
        return (matches.isEmpty ? [file] : matches).sorted {
            ($0.trackID ?? Int.max) < ($1.trackID ?? Int.max)
        }
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

    func audioURL(project: Project, file: ProjectScanFile) -> URL? {
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio,
              let inputFolderURL = project.inputFolderURL else { return nil }

        let sourcePath = file.sourceVideo ?? file.relativePath
        guard isSupportedAudioPath(sourcePath) else { return nil }
        return inputFolderURL.appendingPathComponent(sourcePath)
    }

    func sharkTrackPreviewURL(file: ProjectScanFile, project: Project) -> URL? {
        let relativePath = file.sharkTrackPreviewPath ?? file.relativePath
        if isPAMGuardDetectionReview(project: project) {
            return project.rootFolderURL?.appendingPathComponent(relativePath)
        }
        if let rootURL = project.rootFolderURL?.appendingPathComponent(relativePath),
           FileManager.default.fileExists(atPath: rootURL.path) {
            return rootURL
        }
        return project.inputFolderURL?.appendingPathComponent(relativePath)
    }

    func sharkTrackImage(file: ProjectScanFile, project: Project) -> NSImage? {
        guard let previewURL = sharkTrackPreviewURL(file: file, project: project) else {
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

    func clipStartSeconds(project: Project, file: ProjectScanFile) -> Double? {
        guard isPAMGuardDetectionReview(project: project) else { return nil }
        return max(0, file.clipStartSeconds ?? 0)
    }

    func clipDurationSeconds(project: Project, file: ProjectScanFile) -> Double? {
        guard isPAMGuardDetectionReview(project: project) else { return nil }
        return max(0.05, file.clipDurationSeconds ?? file.durationSeconds ?? 1)
    }

    func movePrevious(project: Project) {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
        loadPreview(project: project)
        prewarmNearbyPreviews(project: project)
    }

    func moveNext(project: Project) {
        guard let fileCount = summary?.files.count, selectedIndex < fileCount - 1 else { return }
        selectedIndex += 1
        AppLog.info("Manual audit moved to next index \(selectedIndex)")
        loadPreview(project: project)
        prewarmNearbyPreviews(project: project)
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

    private func prewarmNearbyPreviews(project: Project) {
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio else {
            return
        }

        if isPAMGuardDetectionReview(project: project) {
            prewarmNearbyAudioPreviews(project: project)
        } else {
            prewarmNearbyAudioPreviews(project: project)
        }
    }

    private func prewarmNearbyAudioPreviews(project: Project) {
        guard let files = summary?.files,
              let inputFolderURL = project.inputFolderURL,
              selectedIndex < files.count else {
            return
        }

        let firstIndex = selectedIndex + 1
        let lastIndex = min(selectedIndex + prewarmCount, files.count - 1)
        guard firstIndex <= lastIndex else {
            return
        }

        let indexes = firstIndex...lastIndex
        for index in indexes {
            let file = files[index]
            guard let url = audioURL(project: project, file: file) else {
                AppLog.info("Manual audit prewarm skipped for non-audio source \(file.sourceVideo ?? file.relativePath)")
                continue
            }
            let clipStart = clipStartSeconds(project: project, file: file)
            let clipDuration = clipDurationSeconds(project: project, file: file)
            let cacheKey = previewCacheKey(for: url, clipStartSeconds: clipStart, clipDurationSeconds: clipDuration)

            guard audioPreviewCacheService.cachedPreview(
                for: url,
                clipStartSeconds: clipStart,
                clipDurationSeconds: clipDuration
            ) == nil, prewarmTasks[cacheKey] == nil else {
                continue
            }

            AppLog.info("Manual audit prewarming preview for \(file.relativePath)")
            prewarmTasks[cacheKey] = Task { [inputFolderURL, url, relativePath = file.relativePath, cacheKey, clipStart, clipDuration] in
                do {
                    _ = try await audioPreviewCacheService.preview(
                        from: url,
                        securityScopedURL: inputFolderURL,
                        clipStartSeconds: clipStart,
                        clipDurationSeconds: clipDuration
                    )
                    prewarmTasks[cacheKey] = nil
                    guard !Task.isCancelled else { return }
                    AppLog.info("Manual audit prewarmed preview for \(relativePath)")
                } catch {
                    prewarmTasks[cacheKey] = nil
                    guard !Task.isCancelled else { return }
                    AppLog.info("Manual audit prewarm failed for \(relativePath): \(error.localizedDescription)")
                }
            }
        }
    }

    private func previewCacheKey(
        for url: URL,
        clipStartSeconds: Double? = nil,
        clipDurationSeconds: Double? = nil
    ) -> String {
        guard let clipStartSeconds, let clipDurationSeconds else {
            return url.standardizedFileURL.path
        }
        return "\(url.standardizedFileURL.path)#\(clipStartSeconds)+\(clipDurationSeconds)"
    }

    private func isSupportedAudioPath(_ path: String) -> Bool {
        let audioExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "mp3", "m4a", "caf"]
        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return audioExtensions.contains(pathExtension)
    }

    private func suspicionScore(_ file: ProjectScanFile) -> Double {
        var score = 0.0

        if !file.readable { score += 1_000 }
        if file.qualityFlag.lowercased() != "ok" { score += 100 }
        score += Double(file.qualityReasons.count) * 25
        score += (file.clippingPercent ?? 0) * 10
        score += (file.nearZeroPercent ?? 0)

        if let rms = file.rmsDBFS, rms < -70 {
            score += 40
        }

        if file.durationSeconds == nil {
            score += 30
        }

        return score
    }

    func isPAMGuardDetectionReview(project: Project) -> Bool {
        WorkflowModule.module(for: project.moduleID) == .pamAudio &&
            summary?.files.contains(where: { $0.sharkTrackStatus == ProjectScanStatus.pamguard }) == true
    }
}
