//
//  PAMManualAuditViewModel.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import SwiftData

/// Manual-audit behavior for audio projects and imported PAMGuard detections.
@Observable
@MainActor
final class PAMManualAuditViewModel: ManualAuditViewModel {
    private let audioPreviewCacheService: AudioPreviewCacheServicing

    init(projectScanService: ProjectScanServicing, audioPreviewCacheService: AudioPreviewCacheServicing) {
        self.audioPreviewCacheService = audioPreviewCacheService
        super.init(projectScanService: projectScanService)
    }

    override func reviewTitle(project: Project) -> String {
        isPAMGuardDetectionReview(project: project)
            ? Strings.ManualAudit.detectionReviewTitle
            : Strings.ManualAudit.title
    }

    override func showsPlaybackControls(project: Project) -> Bool {
        true
    }

    override func decisionOptions(project: Project) -> [ManualAuditDecisionValue] {
        [.valid, .unsure, .invalid]
    }

    override func shouldShowReviewAction(project: Project) -> Bool {
        true
    }

    override func reasonConfiguration(for project: Project) -> AuditReasonConfiguration {
        isPAMGuardDetectionReview(project: project)
            ? .pamDetectionReview()
            : .manualAudit()
    }

    override func reviewHeaderText(project: Project) -> String {
        let format = isPAMGuardDetectionReview(project: project)
            ? Strings.ManualAudit.detectionProgressFormat
            : Strings.ManualAudit.sampleProgressFormat
        return "\(project.name) - \(String(format: format, selectedIndex + 1, summary?.files.count ?? 0))"
    }

    override func speciesTaxa(project: Project) -> [SpeciesTaxon] {
        SpeciesCatalog.cetaceans
    }

    override func cancelPreviewWork() {
        super.cancelPreviewWork()
        audioPreviewCacheService.clear()
    }

    override func loadPreview(project: Project) {
        preview = nil
        guard showsPlaybackControls(project: project),
              let file = selectedFile,
              let inputFolderURL = project.inputFolderURL,
              let url = playbackURL(project: project, file: file) else {
            errorMessage = nil
            isLoadingPreview = false
            return
        }

        let clipStart = playbackStartSeconds(project: project, file: file)
        let clipDuration = playbackDurationSeconds(project: project, file: file)
        if let cachedPreview = audioPreviewCacheService.cachedPreview(
            for: url,
            clipStartSeconds: clipStart,
            clipDurationSeconds: clipDuration
        ) {
            preview = cachedPreview
            errorMessage = nil
            isLoadingPreview = false
            return
        }

        isLoadingPreview = true
        Task { [inputFolderURL, url, relativePath = file.relativePath, clipStart, clipDuration] in
            do {
                let loadedPreview = try await audioPreviewCacheService.preview(
                    from: url,
                    securityScopedURL: inputFolderURL,
                    clipStartSeconds: clipStart,
                    clipDurationSeconds: clipDuration
                )
                guard selectedFile?.relativePath == relativePath else { return }
                preview = loadedPreview
                errorMessage = nil
            } catch {
                guard selectedFile?.relativePath == relativePath else { return }
                preview = nil
                errorMessage = error.localizedDescription
            }
            isLoadingPreview = false
        }
    }

    override func sortFiles(_ files: inout [ProjectScanFile], project: Project) {
        if files.contains(where: { $0.pamDetectionStatus == PAMScanStatus.pamguard }) {
            files.sort {
                ($0.pamDetectionID ?? Int.max) < ($1.pamDetectionID ?? Int.max)
            }
        } else {
            super.sortFiles(&files, project: project)
        }
    }

    override func evidenceMetrics(file: ProjectScanFile, project: Project) -> [ManualAuditEvidenceMetric] {
        isPAMGuardDetectionReview(project: project)
            ? pamguardEvidenceMetrics(file)
            : audioEvidenceMetrics(file)
    }

    override func showsQualityMetric(project: Project) -> Bool {
        !isPAMGuardDetectionReview(project: project)
    }

    override func playbackURL(project: Project, file: ProjectScanFile) -> URL? {
        guard let inputFolderURL = project.inputFolderURL else { return nil }
        let sourcePath = file.pamSourceMedia ?? file.relativePath
        guard PAMMediaFileExtensions.previewAudio.contains(URL(fileURLWithPath: sourcePath).pathExtension.lowercased()) else {
            return nil
        }
        return inputFolderURL.appendingPathComponent(sourcePath)
    }

    override func imagePreviewURL(file: ProjectScanFile, project: Project) -> URL? {
        guard isPAMGuardDetectionReview(project: project) else {
            return nil
        }
        return project.rootFolderURL?.appendingPathComponent(file.pamPreviewPath ?? file.relativePath)
    }

    override func playbackStartSeconds(project: Project, file: ProjectScanFile) -> Double? {
        guard isPAMGuardDetectionReview(project: project) else { return nil }
        return max(0, file.clipStartSeconds ?? 0)
    }

    override func playbackDurationSeconds(project: Project, file: ProjectScanFile) -> Double? {
        guard isPAMGuardDetectionReview(project: project) else { return nil }
        return max(0.05, file.clipDurationSeconds ?? file.durationSeconds ?? 1)
    }

    override func workflowStatusAfterSavingDecision(
        reviewedCount: Int,
        totalCount: Int,
        project: Project
    ) -> ProjectWorkflowStatus {
        if isPAMGuardDetectionReview(project: project) {
            return reviewedCount >= totalCount ? .completed : .detectionReviewInProgress
        }
        return reviewedCount >= totalCount ? .manualAuditCompleted : .manualAuditInProgress
    }

    private func isPAMGuardDetectionReview(project: Project) -> Bool {
        summary?.files.contains(where: { $0.pamDetectionStatus == PAMScanStatus.pamguard }) == true
    }

    private func audioEvidenceMetrics(_ file: ProjectScanFile) -> [ManualAuditEvidenceMetric] {
        [
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.duration, value: file.durationSeconds.map(formatDuration) ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.sampleRate, value: file.sampleRateHz.map { "\($0) Hz" } ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.channels, value: file.channels.map(String.init) ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.bitDepth, value: file.bitDepth.map { "\($0) bit" } ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.peak, value: file.peakDBFS.map { String(format: "%.1f dBFS", $0) } ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.rms, value: file.rmsDBFS.map { String(format: "%.1f dBFS", $0) } ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.clipping, value: file.clippingPercent.map { String(format: "%.3f%%", $0) } ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.nearZero, value: file.nearZeroPercent.map { String(format: "%.1f%%", $0) } ?? Strings.Common.unknown)
        ]
    }

    private func pamguardEvidenceMetrics(_ file: ProjectScanFile) -> [ManualAuditEvidenceMetric] {
        var metrics = [
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.detectionID, value: detectionIdentifier(for: file)),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.startTime, value: metadataValue(file, key: Strings.ManualAudit.startTime)),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.endTime, value: metadataValue(file, key: Strings.ManualAudit.endTime)),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.format, value: file.format ?? Strings.Common.unknown),
            ManualAuditEvidenceMetric(title: Strings.ManualAudit.duration, value: file.durationSeconds.map(formatDuration) ?? Strings.Common.unknown)
        ]
        if let confidence = file.pamConfidence {
            metrics.append(ManualAuditEvidenceMetric(
                title: Strings.ManualAudit.confidence,
                value: confidence.formatted(.number.precision(.fractionLength(2)))
            ))
        }
        return metrics
    }

    private func detectionIdentifier(for file: ProjectScanFile) -> String {
        if let detectionID = file.pamDetectionID {
            return "\(detectionID)"
        }

        return file.relativePath
            .replacingOccurrences(of: "pamguard/events/", with: "")
            .replacingOccurrences(of: "pamguard/detections/", with: "")
            .replacingOccurrences(of: ".png", with: "")
    }

    private func metadataValue(_ file: ProjectScanFile, key: String) -> String {
        let prefix = "\(key):"
        return file.qualityReasons
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? Strings.Common.unknown
    }
}
