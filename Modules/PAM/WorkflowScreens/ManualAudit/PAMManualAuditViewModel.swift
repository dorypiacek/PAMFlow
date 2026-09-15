//
//  PAMManualAuditViewModel.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import UI
import Core
import SwiftData
import AppKit

/// Manual-audit behavior for audio projects and imported PAMGuard detections.
@Observable
@MainActor
final class PAMManualAuditViewModel: ManualAuditViewModel {
    private static let previewCacheRadius = 5

    private let audioPreviewCacheService: AudioPreviewCacheServicing
    private var previewLoadTask: Task<Void, Never>?
    private var resolvedAudioURLs: [String: URL] = [:]
    var preview: AudioPreview?

    init(projectScanService: ProjectScanServicing, audioPreviewCacheService: AudioPreviewCacheServicing) {
        self.audioPreviewCacheService = audioPreviewCacheService
        super.init(projectScanService: projectScanService)
    }

    override func reviewTitle(project: Project) -> String {
        isPAMGuardDetectionReview(project: project)
            ? Strings.ManualAudit.detectionReviewTitle
            : Strings.ManualAudit.title
    }

    override func decisionOptions(project: Project) -> [ManualAuditDecisionValue] {
        [.valid, .unsure, .invalid]
    }

    override func shouldShowReviewAction(project: Project) -> Bool {
        true
    }

    override func reasonConfiguration(for project: Project) -> AuditReasonConfiguration {
        if isPAMGuardDetectionReview(project: project) {
            return AuditReasonConfiguration(
                title: Strings.AuditReason.addReason,
                options: [Strings.AuditReason.falsePositive, Strings.Common.other],
                textOnly: false,
                isRequired: true
            )
        }
        return .manualAudit()
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
        previewLoadTask?.cancel()
        previewLoadTask = nil
        resolvedAudioURLs.removeAll(keepingCapacity: false)
        preview = nil
        audioPreviewCacheService.clear()
    }

    override func loadPreview(project: Project) {
        previewLoadTask?.cancel()
        previewLoadTask = nil
        preview = nil
        guard let file = selectedFile,
              let url = playbackURL(project: project, file: file) else {
            errorMessage = nil
            isLoadingPreview = false
            preheatPreviewWindow(project: project)
            return
        }
        let securityScopedURL = securityScopedURL(for: url, project: project)

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
            preheatPreviewWindow(project: project)
            return
        }

        isLoadingPreview = true
        previewLoadTask = Task { [securityScopedURL, url, relativePath = file.relativePath, clipStart, clipDuration] in
            do {
                let loadedPreview = try await audioPreviewCacheService.preview(
                    from: url,
                    securityScopedURL: securityScopedURL,
                    clipStartSeconds: clipStart,
                    clipDurationSeconds: clipDuration
                )
                guard !Task.isCancelled else { return }
                guard selectedFile?.relativePath == relativePath else { return }
                preview = loadedPreview
                errorMessage = nil
                preheatPreviewWindow(project: project)
            } catch {
                guard !Task.isCancelled else { return }
                guard selectedFile?.relativePath == relativePath else { return }
                preview = nil
                errorMessage = error.localizedDescription
                preheatPreviewWindow(project: project)
            }
            isLoadingPreview = false
        }
        preheatPreviewWindow(project: project)
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

    override func showsFileNameMetric(project: Project) -> Bool {
        !isPAMGuardDetectionReview(project: project)
    }

    func playbackURL(project: Project, file: ProjectScanFile) -> URL? {
        let sourcePath = file.pamSourceMedia ?? file.relativePath
        if let cachedURL = resolvedAudioURLs[sourcePath] {
            return cachedURL
        }

        guard let resolvedURL = firstExistingAudioURL(sourcePath: sourcePath, project: project) else {
            return nil
        }
        resolvedAudioURLs[sourcePath] = resolvedURL
        return resolvedURL
    }

    func playbackStartSeconds(project: Project, file: ProjectScanFile) -> Double? {
        guard isPAMGuardDetectionReview(project: project) else { return nil }
        return max(0, file.clipStartSeconds ?? 0)
    }

    func playbackDurationSeconds(project: Project, file: ProjectScanFile) -> Double? {
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
        var metrics: [ManualAuditEvidenceMetric] = []
        appendMetric(Strings.ManualAudit.duration, file.durationSeconds.map(formatDuration), to: &metrics)
        appendMetric(Strings.ExportFields.sourceMedia, file.pamSourceMedia, to: &metrics)
        appendMetric(Strings.ManualAudit.startTime, metadataValue(file, key: Strings.ManualAudit.startTime), to: &metrics)
        appendMetric(Strings.ManualAudit.endTime, metadataValue(file, key: Strings.ManualAudit.endTime), to: &metrics)
        appendMetric(Strings.ExportFields.detectors, normalizedDetectors(metadataValue(file, key: Strings.ExportFields.detectors)), to: &metrics)
        appendCountMetric(Strings.ExportFields.clickCount, metadataValue(file, key: Strings.ExportFields.clickCount), to: &metrics)
        appendCountMetric(Strings.ExportFields.clickBoutCount, metadataValue(file, key: Strings.ExportFields.clickBoutCount), to: &metrics)
        appendCountMetric(Strings.ExportFields.clickTrainCount, metadataValue(file, key: Strings.ExportFields.clickTrainCount), to: &metrics)
        appendCountMetric(Strings.ExportFields.whistleCount, metadataValue(file, key: Strings.ExportFields.whistleCount), to: &metrics)
        appendMetric("Low Freq (Hz)", metadataValue(file, key: "Low Freq (Hz)"), to: &metrics)
        appendMetric("High Freq (Hz)", metadataValue(file, key: "High Freq (Hz)"), to: &metrics)
        appendMetric(Strings.ManualAudit.format, file.format, to: &metrics)
        appendMetric(Strings.ManualAudit.sampleRate, file.sampleRateHz.map { "\($0) Hz" }, to: &metrics)
        appendMetric(Strings.ManualAudit.channels, file.channels.map(String.init), to: &metrics)
        appendMetric(Strings.ManualAudit.bitDepth, file.bitDepth.map { "\($0) bit" }, to: &metrics)
        return metrics
    }

    private func metadataValue(_ file: ProjectScanFile, key: String) -> String {
        if let attributeValue = file.attributes.string(key)
            ?? file.attributes.string(key.snakeCased()) {
            return attributeValue
        }

        let prefix = "\(key):"
        return file.qualityReasons
            .first { $0.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? Strings.Common.unknown
    }

    private func appendMetric(_ title: String, _ value: String?, to metrics: inout [ManualAuditEvidenceMetric]) {
        guard let value = value?.trimmed,
              !value.isEmpty,
              value.localizedCaseInsensitiveCompare(Strings.Common.unknown) != .orderedSame else {
            return
        }
        metrics.append(ManualAuditEvidenceMetric(title: title, value: value))
    }

    private func appendCountMetric(_ title: String, _ value: String?, to metrics: inout [ManualAuditEvidenceMetric]) {
        guard let value = value?.trimmed,
              let count = Int(value),
              count > 0 else {
            return
        }
        metrics.append(ManualAuditEvidenceMetric(title: title, value: "\(count)"))
    }

    private func normalizedDetectors(_ value: String) -> String? {
        guard value.localizedCaseInsensitiveCompare(Strings.Common.unknown) != .orderedSame else {
            return nil
        }

        let normalized = value
            .replacingOccurrences(of: "Clicks", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "Whistlesmoans", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "Contours", with: "", options: [.caseInsensitive])
            .split(separator: ",")
            .map { collapsedRepeatedPhrase(String($0).trimmed) }
            .filter { !$0.isEmpty }

        var uniqueValues: [String] = []
        for detector in normalized {
            if !uniqueValues.contains(where: { $0.localizedCaseInsensitiveCompare(detector) == .orderedSame }) {
                uniqueValues.append(detector)
            }
        }

        return uniqueValues.joined(separator: ", ").nilIfEmpty
    }

    private func collapsedRepeatedPhrase(_ value: String) -> String {
        let words = value.split(separator: " ").map(String.init)
        guard words.count.isMultiple(of: 2), !words.isEmpty else {
            return value
        }

        let midpoint = words.count / 2
        let firstHalf = words[..<midpoint].joined(separator: " ")
        let secondHalf = words[midpoint...].joined(separator: " ")
        return firstHalf.localizedCaseInsensitiveCompare(secondHalf) == .orderedSame ? firstHalf : value
    }

    private func firstExistingAudioURL(sourcePath: String, project: Project) -> URL? {
        var bases = [project.inputFolderURL, project.rawInputFolderURL]
        if let sourceFolderURL = project.rootFolderURL?.appendingPathComponent(ProjectFileNames.sourceDirectory) {
            bases.append(sourceFolderURL)
        }
        bases.append(project.rootFolderURL)

        return firstExistingURL(
            path: sourcePath,
            relativeFallbackPath: sourcePath,
            bases: bases,
            allowedExtensions: PAMMediaFileExtensions.previewAudio
        )
    }

    func preheatPreviewWindow(project: Project) {
        guard let files = summary?.files,
              !files.isEmpty else {
            return
        }

        let lowerBound = max(files.startIndex, selectedIndex - Self.previewCacheRadius)
        let upperBound = min(files.endIndex - 1, selectedIndex + Self.previewCacheRadius)
        var retainedKeys = Set<String>()

        for index in lowerBound...upperBound {
            let file = files[index]
            guard let url = playbackURL(project: project, file: file) else {
                continue
            }
            let clipStart = playbackStartSeconds(project: project, file: file)
            let clipDuration = playbackDurationSeconds(project: project, file: file)
            retainedKeys.insert(audioPreviewCacheService.cacheKey(
                for: url,
                clipStartSeconds: clipStart,
                clipDurationSeconds: clipDuration
            ))

            guard index != selectedIndex else { continue }
            audioPreviewCacheService.preheat(
                url: url,
                securityScopedURL: securityScopedURL(for: url, project: project),
                clipStartSeconds: clipStart,
                clipDurationSeconds: clipDuration
            )
        }

        audioPreviewCacheService.retainOnly(keys: retainedKeys)
    }

    private func firstExistingURL(
        path: String,
        relativeFallbackPath: String,
        bases: [URL?],
        allowedExtensions: Set<String>,
        additionalPaths: [String] = []
    ) -> URL? {
        let candidatePaths = ([path, relativeFallbackPath] + additionalPaths).filter { !$0.isEmpty }.uniqueStrings()
        let resolvedBases = bases.compactMap { $0 }.uniqueStandardizedURLs()

        for candidatePath in candidatePaths {
            let candidateURL = URL(fileURLWithPath: candidatePath)
            if candidateURL.isFileURL,
               candidateURL.path.hasPrefix("/"),
               allowedExtensions.contains(candidateURL.pathExtension.lowercased()),
               FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            for baseURL in resolvedBases {
                let url = baseURL.appendingPathComponent(candidatePath)
                if allowedExtensions.contains(url.pathExtension.lowercased()),
                   FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }

            if let foundURL = findFile(namedLike: candidatePath, under: resolvedBases, allowedExtensions: allowedExtensions) {
                return foundURL
            }
        }

        return nil
    }

    private func securityScopedURL(for url: URL, project: Project) -> URL {
        let candidates = [
            project.inputFolderURL,
            project.rawInputFolderURL,
            project.rootFolderURL
        ].compactMap { $0 }

        return candidates.first { url.path.hasPrefix($0.path) } ?? project.inputFolderURL ?? url
    }

    private func findFile(namedLike path: String, under baseURLs: [URL], allowedExtensions: Set<String>) -> URL? {
        let targetName = URL(fileURLWithPath: path).lastPathComponent
        guard !targetName.isEmpty else { return nil }

        for baseURL in baseURLs {
            let accessed = baseURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    baseURL.stopAccessingSecurityScopedResource()
                }
            }

            guard let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard isFileMatch(url: url, targetName: targetName, allowedExtensions: allowedExtensions) else {
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values?.isRegularFile == true || values?.isSymbolicLink == true {
                    return url
                }
            }
        }

        return nil
    }

    private func isFileMatch(url: URL, targetName: String, allowedExtensions: Set<String>) -> Bool {
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }

        if url.lastPathComponent == targetName {
            return true
        }

        let targetStem = URL(fileURLWithPath: targetName).deletingPathExtension().lastPathComponent
        guard !targetStem.isEmpty else { return false }
        return url.deletingPathExtension().lastPathComponent == targetStem
    }
}

private extension String {
    func snakeCased() -> String {
        unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                result.append(Character(scalar).lowercased())
            } else if !result.hasSuffix("_") {
                result.append("_")
            }
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}
