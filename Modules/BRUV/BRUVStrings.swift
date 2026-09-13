//
//  BRUVStrings.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation

/// User-facing copy owned by the BRUV module.
enum BRUVStrings {
    enum Module {
        nonisolated static let bruvTitle = "BRUV Video"
        nonisolated static let bruvSubtitle = "Video files for SharkTrack detection review."
        nonisolated static let ruvTitle = "RUV Images"
        nonisolated static let ruvSubtitle = "Image batches for SharkTrack detection review."
        nonisolated static let bruvFolderName = "BRUV Video"
        nonisolated static let ruvFolderName = "RUV Images"
    }

    enum Overview {
        static let preparing = "Preparing SharkTrack detections..."
        static let ready = "SharkTrack detections are ready."
        static let readyNotice = "Ready to process detections with SharkTrack."
    }

    enum ManualAudit {
        static let sharkTrackStatus = "SharkTrack status"
    }

    enum Processing {
        static let title = "Processing Detections"
        static let subtitle = "SharkTrack is finding candidate animals for frame review."
        static let preparingMessage = "Preparing SharkTrack..."
        static let processingFileFormat = "Processing file %d/%d: %@"
        static let processingFrameFormat = "Processing frame %d/%d"
        static let remainingFormat = "About %@ remaining"
        static let estimatingRemaining = "Estimating time remaining..."
        static let silentRuntimeFormat = "Processing for %@. SharkTrack has not reported frame progress yet."
        static let processingDetectionFormat = "%d detections found"
        static let finalizingMessage = "Finalizing detections..."
        static let failedMessage = "SharkTrack processing failed."
        static let noDetectionsMessage = "No review frames were created."
        static let unknownDuration = "unknown time"
        static let retryButton = "Retry Processing"
    }

    enum Progress {
        nonisolated static let started = "SharkTrack processing started."
        nonisolated static let simulatedCompletedFormat = "Simulated SharkTrack processing completed with %d detections."
        nonisolated static let completedFormat = "SharkTrack processing completed with %d detections."
    }
}
