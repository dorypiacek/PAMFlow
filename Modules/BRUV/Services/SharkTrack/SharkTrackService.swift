//
//  SharkTrackService.swift
//  PAMFlow
//
//  Created by Dory on 18/06/2026.
//

import Foundation
import UI
import Core
import SharkTrackKit

/// SharkTrack pre-audit preparation boundary for BRUV and RUV workflows.
protocol SharkTrackServicing: Sendable {
    @MainActor
    func prepareInitialAuditBatch(
        for project: Project,
        onProgress: @escaping @Sendable (SharkTrackPreparationProgress) -> Void
    ) async throws
}

/// Coordinates SharkTrack pre-audit processing for BRUV video and RUV image workflows.
nonisolated final class SharkTrackService: SharkTrackServicing {
    nonisolated static let simulateSharkTrackUserDefaultsKey = "simulateSharkTrackProcessing"

    private let configuration: SharkTrackPreparationConfiguration
    private let fileSystem: SharkTrackFileSystem
    private let processorFactory: SharkTrackProcessorFactory
    private let mediaDiscovery: SharkTrackMediaDiscovery
    private let outputWriter: SharkTrackOutputWriter
    private let summaryStore: SharkTrackSummaryStore
    private let manifestStore: SharkTrackManifestStore
    private let simulationService: SharkTrackSimulationServicing
    private let isSimulationEnabled: @Sendable () -> Bool

    init(
        configuration: SharkTrackPreparationConfiguration = .default,
        fileManager: FileManager = .default,
        processorFactory: SharkTrackProcessorFactory = .bundledRuntime,
        mediaDiscovery: SharkTrackMediaDiscovery = .default,
        outputWriter: SharkTrackOutputWriter = .default,
        summaryStore: SharkTrackSummaryStore = .default,
        manifestStore: SharkTrackManifestStore = .default,
        simulationService: SharkTrackSimulationServicing = SharkTrackSimulationService.default,
        isSimulationEnabled: @escaping @Sendable () -> Bool = SharkTrackService.defaultSimulationFlag
    ) {
        self.configuration = configuration
        self.fileSystem = SharkTrackFileSystem(fileManager)
        self.processorFactory = processorFactory
        self.mediaDiscovery = mediaDiscovery
        self.outputWriter = outputWriter
        self.summaryStore = summaryStore
        self.manifestStore = manifestStore
        self.simulationService = simulationService
        self.isSimulationEnabled = isSimulationEnabled
    }

    @MainActor
    func prepareInitialAuditBatch(
        for project: Project,
        onProgress: @escaping @Sendable (SharkTrackPreparationProgress) -> Void = { _ in }
    ) async throws {
        let context = try SharkTrackPreparationContext(project: project)
        AppLog.module("SharkTrack", "Preparation requested for project '\(context.projectName)'")

        do {
            try await prepareInitialAuditBatch(context: context, onProgress: onProgress)
            AppLog.module("SharkTrack", "Preparation completed for project '\(context.projectName)'")
        } catch {
            AppLog.module("SharkTrack", "Preparation failed for project '\(context.projectName)': \(error.localizedDescription)")
            throw error
        }
    }

    nonisolated private func prepareInitialAuditBatch(
        context: SharkTrackPreparationContext,
        onProgress: @escaping @Sendable (SharkTrackPreparationProgress) -> Void
    ) async throws {
        try await withSecurityScopedAccess(input: context.inputFolderURL, project: context.projectRootURL) {
            let paths = SharkTrackProjectPaths(root: context.projectRootURL, configuration: configuration)
            try paths.createRequiredDirectories(fileSystem: fileSystem)

            onProgress(.preparing)
            AppLog.module("SharkTrack", "Creating output folder \(paths.detections.path)")
            try manifestStore.write(
                .running(
                    module: context.module,
                    projectName: context.projectName,
                    inputFolderURL: context.inputFolderURL,
                    outputFolderURL: paths.detections,
                    message: BRUVStrings.Progress.started
                ),
                to: paths.manifest
            )

            let detections: [SharkTrackDetectionOutput]
            let wasSimulated: Bool

            if isSimulationEnabled() {
                AppLog.module("SharkTrack", "Using simulated SharkTrack output")
                detections = try simulationService.makeDetections(
                    module: context.module,
                    outputURL: paths.detections,
                    projectRootURL: context.projectRootURL
                )
                wasSimulated = true
            } else {
                AppLog.module("SharkTrack", "Running SharkTrackKit on \(context.inputFolderURL.path)")
                let result = try await processMediaFiles(
                    module: context.module,
                    inputFolderURL: context.inputFolderURL,
                    outputURL: paths.internalOutput,
                    onProgress: onProgress
                )
                detections = try outputWriter.writeDetections(
                    from: result,
                    module: context.module,
                    outputURL: paths.detections,
                    projectRootURL: context.projectRootURL
                )
                AppLog.module("SharkTrack", "SharkTrackKit produced \(detections.count) review detections")
                try? fileSystem.removeItem(at: paths.internalOutput)
                wasSimulated = false
            }

            onProgress(.processingDetection(detections.count))
            onProgress(.finalizing)
            try summaryStore.replaceFiles(
                at: paths.scanSummary,
                with: detections,
                displayInputFolderURL: context.displayInputFolderURL,
                wasSimulated: wasSimulated
            )
            try manifestStore.write(
                .completed(
                    module: context.module,
                    projectName: context.projectName,
                    inputFolderURL: context.inputFolderURL,
                    outputFolderURL: paths.detections,
                    detectionCount: detections.count,
                    wasSimulated: wasSimulated
                ),
                to: paths.manifest
            )
        }
    }

    nonisolated private func processMediaFiles(
        module: BRUVProjectType,
        inputFolderURL: URL,
        outputURL: URL,
        onProgress: @escaping @Sendable (SharkTrackPreparationProgress) -> Void
    ) async throws -> SharkTrackResult {
        let files = mediaDiscovery.mediaFiles(module: module, in: inputFolderURL)
        let processor = try processorFactory.makeProcessor()
        var accumulator = SharkTrackResultAccumulator(outputURL: outputURL, processedFileCount: files.count)

        for (offset, fileURL) in files.enumerated() {
            AppLog.module("SharkTrack", "Processing file \(offset + 1)/\(files.count): \(fileURL.path)")
            onProgress(.processingFile(current: offset + 1, total: files.count, name: fileURL.lastPathComponent))

            do {
                for try await event in processor.events(input: fileURL, output: outputURL, options: .maxNReview) {
                    SharkTrackEventMapper.handle(
                        event,
                        fileURL: fileURL,
                        collectedScreenshotCount: accumulator.screenshotCount,
                        onProgress: onProgress,
                        onCompleted: { accumulator.append($0) }
                    )
                }
            } catch {
                AppLog.module("SharkTrack", "Runtime failed for \(fileURL.path): \(error.localizedDescription)")
                throw error
            }
        }

        return accumulator.result()
    }

    nonisolated private func withSecurityScopedAccess<T>(
        input: URL,
        project: URL,
        operation: () async throws -> T
    ) async throws -> T {
        let accessedInput = input.startAccessingSecurityScopedResource()
        let accessedProject = project.startAccessingSecurityScopedResource()
        AppLog.module("SharkTrack", "Security scopes input=\(accessedInput) project=\(accessedProject)")
        defer {
            if accessedInput {
                input.stopAccessingSecurityScopedResource()
            }
            if accessedProject {
                project.stopAccessingSecurityScopedResource()
            }
        }

        return try await operation()
    }

    nonisolated private static func defaultSimulationFlag() -> Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: simulateSharkTrackUserDefaultsKey)
        #else
        false
        #endif
    }
}
