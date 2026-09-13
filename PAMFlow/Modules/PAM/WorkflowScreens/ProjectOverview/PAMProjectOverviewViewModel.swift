//
//  PAMProjectOverviewViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Audio project overview behavior layered on top of the shared overview ViewModel.
@Observable
@MainActor
final class PAMProjectOverviewViewModel: NewProjectOverviewViewModel {
    /// Service used to prepare cached audio snippets for manual audit.
    private let audioPreviewCacheService: AudioPreviewCacheServicing

    /// Creates an audio-aware overview ViewModel with shared scan loading and preview caching services.
    init(
        projectScanService: ProjectScanServicing,
        audioPreviewCacheService: AudioPreviewCacheServicing
    ) {
        self.audioPreviewCacheService = audioPreviewCacheService
        super.init(projectScanService: projectScanService)
    }

    /// Loads the shared scan summary and warms the first audio previews for manual audit.
    override func load(project: Project) {
        super.load(project: project)
        guard let summary,
              let inputFolderURL = project.inputFolderURL else {
            return
        }

        let previewableExtensions = PAMMediaFileExtensions.previewAudio
        for file in summary.files.prefix(Metrics.Cache.manualAuditPrewarmCount + 1)
            where previewableExtensions.contains(URL(fileURLWithPath: file.relativePath).pathExtension.lowercased()) {
            audioPreviewCacheService.preheat(
                url: inputFolderURL.appendingPathComponent(file.relativePath),
                securityScopedURL: inputFolderURL,
                clipStartSeconds: nil,
                clipDurationSeconds: nil
            )
        }
    }
}
