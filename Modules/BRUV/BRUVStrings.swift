//
//  BRUVStrings.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import UI
import Core

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
        static let title = "Detection Review"
        static let sharkTrackStatus = "SharkTrack status"
    }

    enum ProjectSelection {
        static let detectionReviewProgressPrefix = "Detection review:"
        static let detectionReviewInProgress = "Detection review in progress"
        static let detectionReviewCompleted = "Detection review completed"
        static let continueDetectionReview = "Continue Detection Review"
        static let openDetectionOverview = "Open Detection Overview"
    }

    enum ProjectOverview {
        static let title = "Project Overview"
        static let subtitle = "Review the scan results before Detection Review starts."
        static let detectionReviewProgress = "Detection review progress"
        static let detectionsByVideo = "Detections by video"
        static let frameRates = "Frame rates found"
        static let processedVideos = "Processed videos"
        static let ready = "Ready for detection review"
        static let startDetectionReview = "Start Detection Review"
        static let continueDetectionReview = "Continue Detection Review"
        static let openDetectionOverview = "Open Detection Overview"
        static let videoFiles = "video files"
    }

    enum ScanWarnings {
        static let noVideoFilesFound = "No video files were found in the selected folder."
        static let noImageFilesFound = "No image files were found in the selected folder."
        static let unreadableFilesFound = "Some files could not be read."
        static let multipleFormatsFound = "Multiple file formats found."
        static let multipleResolutionsFound = "Multiple resolutions found."
        static let lowResolutionFound = "Some files have low resolution."
        static let largeBatch = "This batch is large and may take a while."
        static let imageMetadataUnreadable = "Could not read image metadata."
        static let videoTrackUnreadable = "No video track was found."
        static let videoMetadataUnreadable = "Could not read video metadata."
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

    enum Completion {
        static let title = "Project Complete"
        static let subtitle = "Review the final visual detection summary."
        static let complete = "Complete"
        static let backToProjects = "Back to Projects"
        static let exportDetections = "Export Detections"
        static let exportSuccessFormat = "Exported %@"
        static let projectOverview = "Project Overview"
        static let project = "Project"
        static let processedBy = "Processed By"
        static let reviewedFiles = "Reviewed Files"
        static let validDecisions = "Valid Decisions"
        static let invalidDecisions = "Invalid Decisions"
        static let unsureDecisions = "Unsure Decisions"
    }
}
