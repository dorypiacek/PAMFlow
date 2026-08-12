//
//  Dependencies.swift
//  PAMFlow
//
//  Created by Dory on 07/06/2026.
//

import Foundation

/// Shared app services injected into feature models.
@MainActor
struct Dependencies {
    let projectFileService: ProjectFileServicing
    let projectScanService: ProjectScanServicing
    let audioPreviewCacheService: AudioPreviewCacheServicing
    let sharkTrackService: SharkTrackServicing
    let pamGuardPreparationService: PAMGuardPreparationServicing
    let pamGuardDetectionProcessingService: PAMGuardDetectionProcessingServicing
    let fileSelectionService: FileSelecting
}
