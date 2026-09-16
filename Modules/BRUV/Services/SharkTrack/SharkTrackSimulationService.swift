//
//  SharkTrackSimulationService.swift
//  PAMFlow
//
//  Created by Dory on 10/08/2026.
//

import Foundation
import UI
import Core

/// Simulation boundary for local SharkTrack demo detections.
protocol SharkTrackSimulationServicing: Sendable {
    nonisolated func makeDetections(
        module: BRUVProjectType,
        outputURL: URL,
        projectRootURL: URL
    ) throws -> [SharkTrackDetectionOutput]
}

nonisolated struct SharkTrackSimulationService: SharkTrackSimulationServicing {
    private enum SimulationAssets {
        static let screenshotExtension = "jpg"
    }

    private let bundle: SharkTrackResourceBundling
    private let fileSystem: SharkTrackFileSystem
    private let outputWriter: SharkTrackOutputWriter

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        outputWriter: SharkTrackOutputWriter = .default
    ) {
        self.bundle = SharkTrackResourceBundle(bundle)
        self.fileSystem = SharkTrackFileSystem(fileManager)
        self.outputWriter = outputWriter
    }

    static let `default` = SharkTrackSimulationService()

    func makeDetections(
        module: BRUVProjectType,
        outputURL: URL,
        projectRootURL: URL
    ) throws -> [SharkTrackDetectionOutput] {
        let screenshots = simulationScreenshots()
        guard !screenshots.isEmpty else {
            throw SharkTrackPreparationError.missingSimulationInputs
        }

        let detections = try screenshots.map {
            try copy($0, module: module, outputURL: outputURL, projectRootURL: projectRootURL)
        }

        return withMaxN(detections)
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private func copy(
        _ screenshot: SimulationScreenshot,
        module: BRUVProjectType,
        outputURL: URL,
        projectRootURL: URL
    ) throws -> SharkTrackDetectionOutput {
        let destinationRoot = outputWriter.finalDetectionFolder(
            module: module,
            outputURL: outputURL,
            sourceFolderName: screenshot.outputFolderName
        )
        try fileSystem.createDirectory(at: destinationRoot)

        let destinationURL = outputWriter.uniqueFileURL(for: screenshot.url.lastPathComponent, in: destinationRoot)
        if fileSystem.fileExists(atPath: destinationURL.path) {
            try fileSystem.removeItem(at: destinationURL)
        }
        try fileSystem.copyItem(at: screenshot.url, to: destinationURL)

        return SharkTrackDetectionOutput(
            fileURL: destinationURL,
            relativePath: RelativePath.url(destinationURL, relativeTo: projectRootURL),
            sourceVideoName: screenshot.sourceVideoName,
            trackID: screenshot.trackID,
            frameNumber: nil,
            maxN: nil,
            status: SimulationScreenshot.status,
            timestamp: nil,
            confidence: nil
        )
    }

    private func simulationScreenshots() -> [SimulationScreenshot] {
        bundle.urls(forResourcesWithExtension: SimulationAssets.screenshotExtension)
            .filter { $0.lastPathComponent.hasSuffix(SimulationScreenshot.fileSuffix) }
            .compactMap(SimulationScreenshot.init(url:))
            .sorted()
    }

    private func withMaxN(_ detections: [SharkTrackDetectionOutput]) -> [SharkTrackDetectionOutput] {
        let countsByFrame = detections.reduce(into: [String: Int]()) { partialResult, detection in
            partialResult[maxNKey(for: detection), default: 0] += 1
        }

        return detections.map { detection in
            guard detection.maxN == nil else { return detection }
            let count = countsByFrame[maxNKey(for: detection)] ?? 1
            return SharkTrackDetectionOutput(
                fileURL: detection.fileURL,
                relativePath: detection.relativePath,
                sourceVideoName: detection.sourceVideoName,
                trackID: detection.trackID,
                frameNumber: detection.frameNumber,
                maxN: max(1, count),
                status: detection.status,
                timestamp: detection.timestamp,
                confidence: detection.confidence
            )
        }
    }

    private func maxNKey(for detection: SharkTrackDetectionOutput) -> String {
        let source = detection.sourceVideoName ?? detection.fileURL.deletingLastPathComponent().lastPathComponent
        if let frameNumber = detection.frameNumber {
            return "\(source)#frame:\(frameNumber)"
        }
        if let timestamp = detection.timestamp {
            return "\(source)#time:\(Int((timestamp * 10).rounded()))"
        }
        return "\(source)#track:\(detection.trackID)"
    }
}

/// Resource lookup boundary for simulation screenshots.
protocol SharkTrackResourceBundling: Sendable {
    nonisolated func urls(forResourcesWithExtension pathExtension: String) -> [URL]
}

nonisolated struct SharkTrackResourceBundle: @unchecked Sendable, SharkTrackResourceBundling {
    private let bundle: Bundle

    init(_ bundle: Bundle) {
        self.bundle = bundle
    }

    func urls(forResourcesWithExtension pathExtension: String) -> [URL] {
        bundle.urls(forResourcesWithExtension: pathExtension, subdirectory: nil) ?? []
    }
}

nonisolated private struct SimulationScreenshot: Sendable, Comparable {
    static let fileSuffix = "-elasmobranch.jpg"
    static let status = "simulated"

    let url: URL
    let outputFolderName: String
    let sourceVideoName: String
    let trackID: Int

    init?(url: URL) {
        let id = Int(url.lastPathComponent.split(separator: "-").first ?? "") ?? 0
        guard id > 0 else { return nil }

        let sourceIndex = id <= 10 ? 5 : 4
        self.url = url
        outputFolderName = "A01B07_27.01.2023_L (\(sourceIndex))"
        sourceVideoName = "A01B07_27.01.2023_L (\(sourceIndex)).MP4"
        trackID = id
    }

    static func < (lhs: SimulationScreenshot, rhs: SimulationScreenshot) -> Bool {
        if lhs.trackID == rhs.trackID {
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }

        return lhs.trackID < rhs.trackID
    }
}
