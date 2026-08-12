//
//  SharkTrackProcessingView.swift
//  PAMFlow
//
//  Created by Dory on 19/06/2026.
//

import SwiftData
import SwiftUI

/// Runs SharkTrack processing before BRUV/RUV manual review.
///
/// This screen intentionally mirrors the scan progress screen so processing is
/// presented as a durable workflow step instead of a side effect of the project
/// overview.
struct SharkTrackProcessingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID

    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var statusMessage = Strings.SharkTrackProcessing.preparingMessage
    @State private var currentFileMessage: String?
    @State private var detailMessage: String?
    @State private var processingStartedAt: Date?
    @State private var lastRuntimeProgressAt: Date?
    @State private var hasRuntimeFrameProgress = false
    @State private var batchStartedAt: Date?
    @State private var currentFileIndex = 1
    @State private var totalFileCount = 1
    @State private var progress = 0.0

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    LoadingCardView(
                        title: Strings.SharkTrackProcessing.title,
                        subtitle: Strings.SharkTrackProcessing.subtitle,
                        message: statusMessage,
                        progress: progress,
                        detail: detailMessage,
                        errorMessage: errorMessage
                    ) {
                        if errorMessage != nil {
                            Button(Strings.SharkTrackProcessing.retryButton) {
                                Task {
                                    await processProject()
                                }
                            }
                            .buttonStyle(.primaryAction)
                        }
                    }
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task {
            await processProject()
        }
        .task(id: isProcessing) {
            guard isProcessing else { return }
            await runProgressHeartbeat()
        }
    }

    private func processProject() async {
        guard !isProcessing, let project = fetchProject() else { return }

        let module = WorkflowModule.module(for: project.moduleID)
        guard module.requiresSharkTrack else {
            appCoordinator.openManualAudit(project)
            return
        }

        isProcessing = true
        errorMessage = nil
        statusMessage = Strings.SharkTrackProcessing.preparingMessage
        detailMessage = nil
        processingStartedAt = nil
        lastRuntimeProgressAt = nil
        hasRuntimeFrameProgress = false
        batchStartedAt = nil
        currentFileIndex = 1
        totalFileCount = 1

        do {
            try await appCoordinator.dependencies.sharkTrackService.prepareInitialAuditBatch(for: project) { update in
                Task { @MainActor in
                    apply(update)
                }
            }

            statusMessage = Strings.SharkTrackProcessing.finalizingMessage
            let summary = try appCoordinator.dependencies.projectScanService.loadSummary(for: project)
            project.workflowStatus = summary.fileCount > 0 ? .manualAuditInProgress : .manualAuditCompleted
            project.lastOpenedAt = .now
            try project.storeScanSummary(summary)
            try modelContext.save()

            if summary.fileCount > 0 {
                appCoordinator.openManualAudit(project)
            } else {
                AppLog.sharkTrack("No SharkTrack review detections found; opening overview without error")
                appCoordinator.openManualAuditOverview(project)
            }
        } catch {
            AppLog.sharkTrack("Processing screen failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            statusMessage = Strings.SharkTrackProcessing.failedMessage
        }

        isProcessing = false
    }

    private func apply(_ update: SharkTrackPreparationProgress) {
        switch update {
        case .preparing:
            progress = 0
            statusMessage = Strings.SharkTrackProcessing.preparingMessage
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
            let message = String(format: Strings.SharkTrackProcessing.processingFileFormat, current, total, name)
            currentFileMessage = message
            statusMessage = message
            detailMessage = fileLevelRemainingMessage(current: current, total: total)
            processingStartedAt = .now
            lastRuntimeProgressAt = .now
            hasRuntimeFrameProgress = false
        case .processingProgress(let current, let total, let fraction, _, let remainingSeconds):
            let batchFraction = (Double(max(currentFileIndex - 1, 0)) + fraction) / Double(max(totalFileCount, 1))
            progress = min(max(batchFraction, progress), 0.99)
            let frameMessage = String(format: Strings.SharkTrackProcessing.processingFrameFormat, current, total)
            let etaMessage = remainingSeconds.map { String(format: Strings.SharkTrackProcessing.remainingFormat, formatDuration($0)) } ?? Strings.SharkTrackProcessing.estimatingRemaining
            statusMessage = [currentFileMessage, frameMessage]
                .compactMap { $0 }
                .joined(separator: "\n")
            detailMessage = etaMessage
            lastRuntimeProgressAt = .now
            hasRuntimeFrameProgress = true
        case .processingDetection(let count):
            let detectionProgress = min(0.96, 0.08 + (Double(count) * 0.025))
            progress = max(progress, detectionProgress)
            let detectionMessage = String(format: Strings.SharkTrackProcessing.processingDetectionFormat, count)
            statusMessage = [currentFileMessage, detectionMessage]
                .compactMap { $0 }
                .joined(separator: "\n")
            detailMessage = detailMessage ?? Strings.SharkTrackProcessing.estimatingRemaining
            lastRuntimeProgressAt = .now
        case .finalizing:
            progress = 1
            statusMessage = Strings.SharkTrackProcessing.finalizingMessage
            detailMessage = nil
            processingStartedAt = nil
            lastRuntimeProgressAt = nil
            hasRuntimeFrameProgress = false
            batchStartedAt = nil
        }
    }

    @MainActor
    private func runProgressHeartbeat() async {
        while isProcessing {
            refreshSilentRuntimeStatus()
            try? await Task.sleep(for: .seconds(1))
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
        detailMessage = String(format: Strings.SharkTrackProcessing.silentRuntimeFormat, formatDuration(elapsed))
    }

    private func fileLevelRemainingMessage(current: Int, total: Int) -> String {
        guard total > 1,
              current > 1,
              let batchStartedAt else {
            return Strings.SharkTrackProcessing.estimatingRemaining
        }

        let elapsed = Date.now.timeIntervalSince(batchStartedAt)
        let completed = max(current - 1, 1)
        let remaining = (elapsed / Double(completed)) * Double(max(total - completed, 0))
        return String(format: Strings.SharkTrackProcessing.remainingFormat, formatDuration(remaining))
    }

    private func fetchProject() -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return Strings.SharkTrackProcessing.unknownDuration }
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
