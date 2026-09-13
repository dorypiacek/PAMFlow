//
//  BRUVManualAuditViewModel.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import SwiftData

/// Manual-audit behavior for BRUV/RUV frame and image detections.
@Observable
@MainActor
final class BRUVManualAuditViewModel: ManualAuditViewModel {
    override func reviewTitle(project: Project) -> String {
        Strings.ManualAudit.frameReviewTitle
    }

    override func previewKind(project: Project) -> ManualAuditPreviewKind {
        .image
    }

    override func shouldShowReviewAction(project: Project) -> Bool {
        true
    }

    override func canAssignSpecies(project: Project) -> Bool {
        true
    }

    override func canEditMaxN(project: Project) -> Bool {
        true
    }

    override func speciesTaxa(project: Project) -> [SpeciesTaxon] {
        SpeciesCatalog.elasmobranchs
    }

    override func reviewHeaderText(project: Project) -> String {
        guard let files = summary?.files,
              let selectedFile,
              let sourceVideo = selectedFile.sourceVideo else {
            return "\(project.name) - Detection \(selectedIndex + 1)/\(summary?.files.count ?? 0)"
        }
        var videos: [String] = []
        for video in files.compactMap(\.sourceVideo) where !videos.contains(video) {
            videos.append(video)
        }
        let videoIndex = (videos.firstIndex(of: sourceVideo) ?? 0) + 1
        let videoFiles = files.filter { $0.sourceVideo == sourceVideo }
        let detectionIndex = (videoFiles.firstIndex(where: { $0.relativePath == selectedFile.relativePath }) ?? 0) + 1
        return "\(project.name) - Video \(videoIndex)/\(videos.count) - Detection \(detectionIndex)/\(videoFiles.count)"
    }

    override func sortFiles(_ files: inout [ProjectScanFile], project: Project) {
        files.sort {
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
    }

    override func evidenceMetrics(file: ProjectScanFile, project: Project) -> [ManualAuditEvidenceMetric] {
        var metrics: [ManualAuditEvidenceMetric] = []
        if let trackID = file.trackID {
            metrics.append(ManualAuditEvidenceMetric(title: Strings.ManualAudit.trackID, value: "\(trackID)"))
        }
        if let confidence = file.sharkTrackConfidence {
            metrics.append(ManualAuditEvidenceMetric(
                title: Strings.ManualAudit.confidence,
                value: confidence.formatted(.percent.precision(.fractionLength(0)))
            ))
        }
        if let frameNumber = file.frameNumber {
            metrics.append(ManualAuditEvidenceMetric(title: Strings.ManualAudit.frameNumber, value: "\(frameNumber)"))
        }
        if let width = file.width, let height = file.height {
            metrics.append(ManualAuditEvidenceMetric(title: Strings.ManualAudit.imageSize, value: "\(width) x \(height)"))
        }
        if let format = file.format {
            metrics.append(ManualAuditEvidenceMetric(title: Strings.ManualAudit.format, value: format))
        }
        metrics.append(ManualAuditEvidenceMetric(title: Strings.ManualAudit.fileSize, value: formattedFileSize(file.sizeBytes)))
        if let sharkTrackStatus = file.sharkTrackStatus {
            metrics.append(ManualAuditEvidenceMetric(title: BRUVStrings.ManualAudit.sharkTrackStatus, value: sharkTrackStatus.capitalized))
        }
        return metrics
    }

    override func displaySourceName(for file: ProjectScanFile, project: Project) -> String {
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

    override func imagePreviewURL(file: ProjectScanFile, project: Project) -> URL? {
        let relativePath = file.sharkTrackPreviewPath ?? file.relativePath
        if let rootURL = project.rootFolderURL?.appendingPathComponent(relativePath),
           FileManager.default.fileExists(atPath: rootURL.path) {
            return rootURL
        }
        return project.inputFolderURL?.appendingPathComponent(relativePath)
    }

    override func effectiveMaxN(for file: ProjectScanFile, project: Project, modelContext: ModelContext) -> Int? {
        auditDecision(for: file, project: project, modelContext: modelContext)?.userMaxN ?? file.maxN
    }

    override func speciesAssignmentDrafts(
        for file: ProjectScanFile,
        project: Project,
        modelContext: ModelContext
    ) -> [SpeciesAssignmentDraft] {
        detectionsInCurrentFrame(for: file).map { file in
            SpeciesAssignmentDraft(
                id: file.relativePath,
                primaryLabel: file.trackID.map(String.init) ?? Strings.Common.unknown,
                secondaryLabel: file.sharkTrackConfidence.map {
                    $0.formatted(.percent.precision(.fractionLength(0)))
                } ?? Strings.Common.unknown,
                selection: speciesSelections(
                    for: file,
                    project: project,
                    modelContext: modelContext
                ).first,
                isRemoved: isRemovedFromExport(
                    for: file,
                    project: project,
                    modelContext: modelContext
                )
            )
        }
    }

    override func workflowStatusAfterSavingDecision(
        reviewedCount: Int,
        totalCount: Int,
        project: Project
    ) -> ProjectWorkflowStatus {
        reviewedCount >= totalCount ? .manualAuditCompleted : .manualAuditInProgress
    }

    private func detectionsInCurrentFrame(for file: ProjectScanFile) -> [ProjectScanFile] {
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

    private func isGeneratedVisualOutputName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("elasmobranch") || lowercased.contains("sharktrack")
    }
}
