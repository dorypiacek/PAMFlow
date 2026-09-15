//
//  SharkTrackProcessingViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import UI
import Core
import Observation
import SwiftData

/// Defines state and commands for the BRUV/RUV SharkTrack processing step.
@MainActor
protocol SharkTrackProcessingViewModelType: AnyObject {
    /// User-facing processing failure, if the SharkTrack run cannot complete.
    var errorMessage: String? { get }
    /// Indicates whether SharkTrack processing is currently active.
    var isProcessing: Bool { get }
    /// Primary status text displayed in the progress surface.
    var statusMessage: String { get }
    /// Secondary detail text such as estimated remaining time.
    var detailMessage: String? { get }
    /// Normalized processing progress from `0...1`.
    var progress: Double { get }

    /// Runs SharkTrack preparation for the project and advances the workflow when finished.
    func processProject(modelContext: ModelContext, workflowActions: WorkflowActionHandling) async
    /// Keeps progress moving during SharkTrack runtime phases that do not emit frame callbacks.
    func runProgressHeartbeat() async
}

/// View model for the module-owned SharkTrack processing workflow step.
@Observable
@MainActor
final class SharkTrackProcessingViewModel: SharkTrackProcessingViewModelType {
    /// User-facing processing failure, if the SharkTrack run cannot complete.
    var errorMessage: String?
    /// Indicates whether SharkTrack processing is currently active.
    var isProcessing = false
    /// Primary status text displayed in the progress surface.
    var statusMessage = BRUVStrings.Processing.preparingMessage
    /// Last file-level message emitted by the SharkTrack service.
    var currentFileMessage: String?
    /// Secondary detail text such as estimated remaining time.
    var detailMessage: String?
    /// Start time for the current runtime phase.
    var processingStartedAt: Date?
    /// Last time the external runtime emitted granular progress.
    var lastRuntimeProgressAt: Date?
    /// Indicates whether frame-level progress has been received for the current file.
    var hasRuntimeFrameProgress = false
    /// Start time for the current batch.
    var batchStartedAt: Date?
    /// One-based index of the file currently being processed.
    var currentFileIndex = 1
    /// Number of files in the current processing batch.
    var totalFileCount = 1
    /// Normalized processing progress from `0...1`.
    var progress = 0.0

    /// Identifier of the project being processed.
    private let projectID: UUID
    /// Service that prepares SharkTrack output for detection review.
    private let sharkTrackService: SharkTrackServicing
    /// Service used to reload the scan summary after SharkTrack processing.
    private let projectScanService: ProjectScanServicing

    /// Creates processing state for a persisted visual project.
    init(
        projectID: UUID,
        sharkTrackService: SharkTrackServicing,
        projectScanService: ProjectScanServicing
    ) {
        self.projectID = projectID
        self.sharkTrackService = sharkTrackService
        self.projectScanService = projectScanService
    }

    /// Prepares the initial audit batch, stores the updated scan summary, and opens the next module step.
    func processProject(modelContext: ModelContext, workflowActions: WorkflowActionHandling) async {
        guard !isProcessing, let project = fetchProject(modelContext: modelContext) else { return }

        isProcessing = true
        errorMessage = nil
        statusMessage = BRUVStrings.Processing.preparingMessage
        detailMessage = nil
        processingStartedAt = nil
        lastRuntimeProgressAt = nil
        hasRuntimeFrameProgress = false
        batchStartedAt = nil
        currentFileIndex = 1
        totalFileCount = 1

        do {
            try await sharkTrackService.prepareInitialAuditBatch(for: project) { update in
                Task { @MainActor in
                    self.apply(update)
                }
            }

            statusMessage = BRUVStrings.Processing.finalizingMessage
            let summary = try projectScanService.loadSummary(for: project)
            project.workflowStatus = summary.fileCount > 0 ? .manualAuditInProgress : .manualAuditCompleted
            project.lastOpenedAt = .now
            try project.storeScanSummary(summary)
            try modelContext.save()

            if summary.fileCount == 0 {
                AppLog.module("SharkTrack", "No SharkTrack review detections found; opening overview without error")
            }
            workflowActions.goToNextStep(for: project)
        } catch {
            AppLog.module("SharkTrack", "Processing screen failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            statusMessage = BRUVStrings.Processing.failedMessage
        }

        isProcessing = false
    }

    /// Updates elapsed-time messaging while the external runtime is busy without granular callbacks.
    func runProgressHeartbeat() async {
        while isProcessing {
            refreshSilentRuntimeStatus()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func apply(_ update: SharkTrackPreparationProgress) {
        switch update {
        case .preparing:
            progress = 0
            statusMessage = BRUVStrings.Processing.preparingMessage
            detailMessage = nil
            processingStartedAt = nil
            lastRuntimeProgressAt = nil
            hasRuntimeFrameProgress = false
            batchStartedAt = nil
            currentFileIndex = 1
            totalFileCount = 1
        case .processingFile(let current, let total, let name):
            batchStartedAt = batchStartedAt ?? .now
            currentFileIndex = current
            totalFileCount = max(total, 1)
            let startedFileFraction = Double(max(current - 1, 0)) / Double(max(total, 1))
            progress = max(progress, max(startedFileFraction, 0.03))
            let message = String(format: BRUVStrings.Processing.processingFileFormat, current, total, name)
            currentFileMessage = message
            statusMessage = message
            detailMessage = fileLevelRemainingMessage(current: current, total: total)
            processingStartedAt = .now
            lastRuntimeProgressAt = .now
            hasRuntimeFrameProgress = false
        case .processingProgress(let current, let total, let fraction, _, let remainingSeconds):
            let batchFraction = (Double(max(currentFileIndex - 1, 0)) + fraction) / Double(max(totalFileCount, 1))
            progress = min(max(batchFraction, progress), 0.99)
            let frameMessage = String(format: BRUVStrings.Processing.processingFrameFormat, current, total)
            let etaMessage = remainingSeconds.map { String(format: BRUVStrings.Processing.remainingFormat, formatDuration($0)) } ?? BRUVStrings.Processing.estimatingRemaining
            statusMessage = [currentFileMessage, frameMessage]
                .compactMap { $0 }
                .joined(separator: "\n")
            detailMessage = etaMessage
            lastRuntimeProgressAt = .now
            hasRuntimeFrameProgress = true
        case .processingDetection(let count):
            let detectionProgress = min(0.96, 0.08 + (Double(count) * 0.025))
            progress = max(progress, detectionProgress)
            let detectionMessage = String(format: BRUVStrings.Processing.processingDetectionFormat, count)
            statusMessage = [currentFileMessage, detectionMessage]
                .compactMap { $0 }
                .joined(separator: "\n")
            detailMessage = detailMessage ?? BRUVStrings.Processing.estimatingRemaining
            lastRuntimeProgressAt = .now
        case .finalizing:
            progress = 1
            statusMessage = BRUVStrings.Processing.finalizingMessage
            detailMessage = nil
            processingStartedAt = nil
            lastRuntimeProgressAt = nil
            hasRuntimeFrameProgress = false
            batchStartedAt = nil
        }
    }

    private func refreshSilentRuntimeStatus() {
        guard errorMessage == nil,
              currentFileMessage != nil,
              !hasRuntimeFrameProgress,
              let processingStartedAt else { return }

        let elapsed = Date.now.timeIntervalSince(processingStartedAt)
        guard elapsed >= 3 else { return }

        let fileBase = Double(max(currentFileIndex - 1, 0)) / Double(max(totalFileCount, 1))
        let fileSpan = 0.82 / Double(max(totalFileCount, 1))
        let runtimeFraction = min(0.85, elapsed / 180)
        progress = max(progress, min(fileBase + (fileSpan * runtimeFraction), 0.94))
        detailMessage = String(format: BRUVStrings.Processing.silentRuntimeFormat, formatDuration(elapsed))
    }

    private func fileLevelRemainingMessage(current: Int, total: Int) -> String {
        guard total > 1,
              current > 1,
              let batchStartedAt else {
            return BRUVStrings.Processing.estimatingRemaining
        }

        let elapsed = Date.now.timeIntervalSince(batchStartedAt)
        let completed = max(current - 1, 1)
        let remaining = (elapsed / Double(completed)) * Double(max(total - completed, 0))
        return String(format: BRUVStrings.Processing.remainingFormat, formatDuration(remaining))
    }

    private func fetchProject(modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return BRUVStrings.Processing.unknownDuration }
        let roundedSeconds = Int(seconds.rounded())
        if roundedSeconds < 60 {
            return "\(roundedSeconds)s"
        }

        let minutes = roundedSeconds / 60
        let seconds = roundedSeconds % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }
}
