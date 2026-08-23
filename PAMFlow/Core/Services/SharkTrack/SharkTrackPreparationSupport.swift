//
//  SharkTrackPreparationSupport.swift
//  PAMFlow
//
//  Created by Codex on 10/08/2026.
//

import Foundation
import ImageIO
import SharkTrackKit

/// User-facing progress emitted while SharkTrack prepares review media.
nonisolated enum SharkTrackPreparationProgress: Sendable {
    case preparing
    case processingFile(current: Int, total: Int, name: String)
    case processingProgress(current: Int, total: Int, fraction: Double, elapsedSeconds: TimeInterval, remainingSeconds: TimeInterval?)
    case processingDetection(Int)
    case finalizing
}

nonisolated enum SharkTrackPreparationError: LocalizedError {
    case unsupportedModule
    case missingInputFolder
    case missingProjectFolder
    case missingSimulationInputs

    var errorDescription: String? {
        switch self {
        case .unsupportedModule:
            "SharkTrack is only available for BRUV video and RUV image workflows."
        case .missingInputFolder:
            "Could not open the selected data folder."
        case .missingProjectFolder:
            "Could not open the project folder."
        case .missingSimulationInputs:
            "Could not find the local SharkTrack simulation screenshots."
        }
    }
}

nonisolated struct SharkTrackPreparationConfiguration: Sendable {
    var detectionsDirectoryName: String
    var workDirectoryName: String
    var internalOutputDirectoryName: String
    var scanSummaryFileName: String
    var manifestFileName: String

    static let `default` = SharkTrackPreparationConfiguration(
        detectionsDirectoryName: ProjectFileNames.detectionsDirectory,
        workDirectoryName: ProjectFileNames.workDirectory,
        internalOutputDirectoryName: ProjectFileNames.sharkTrackInternalDirectory,
        scanSummaryFileName: ProjectFileNames.scanSummary,
        manifestFileName: ProjectFileNames.sharkTrackManifest
    )
}

nonisolated struct SharkTrackProjectPaths: Sendable {
    let root: URL
    let detections: URL
    let work: URL
    let internalOutput: URL
    let scanSummary: URL
    let manifest: URL

    init(root: URL, configuration: SharkTrackPreparationConfiguration) {
        self.root = root
        detections = root.appendingPathComponent(configuration.detectionsDirectoryName, isDirectory: true)
        work = root.appendingPathComponent(configuration.workDirectoryName, isDirectory: true)
        internalOutput = work.appendingPathComponent(configuration.internalOutputDirectoryName, isDirectory: true)
        scanSummary = work.appendingPathComponent(configuration.scanSummaryFileName)
        manifest = detections.appendingPathComponent(configuration.manifestFileName)
    }

    func createRequiredDirectories(fileSystem: SharkTrackFileSystem) throws {
        try fileSystem.createDirectory(at: detections)
        try fileSystem.createDirectory(at: internalOutput)
    }
}

nonisolated struct SharkTrackPreparationContext: Sendable {
    let module: WorkflowModule
    let projectName: String
    let inputFolderURL: URL
    let displayInputFolderURL: URL
    let projectRootURL: URL

    init(project: Project) throws {
        module = WorkflowModule.module(for: project.moduleID)
        guard module == .bruvVideo || module == .ruvImages else {
            throw SharkTrackPreparationError.unsupportedModule
        }
        guard let inputFolderURL = project.inputFolderURL else {
            AppLog.sharkTrack("Preparation failed: missing input folder bookmark")
            throw SharkTrackPreparationError.missingInputFolder
        }
        guard let projectRootURL = project.rootFolderURL else {
            AppLog.sharkTrack("Preparation failed: missing project folder bookmark")
            throw SharkTrackPreparationError.missingProjectFolder
        }

        self.projectName = project.name
        self.inputFolderURL = inputFolderURL
        self.displayInputFolderURL = project.rawInputFolderURL ?? inputFolderURL
        self.projectRootURL = projectRootURL
    }
}

nonisolated struct SharkTrackProcessorFactory: Sendable {
    var makeProcessor: @Sendable () throws -> SharkTrackProcessor

    static let installedRuntime = SharkTrackProcessorFactory {
        SharkTrackProcessor()
    }

    static let bundledRuntime = SharkTrackProcessorFactory {
        if let resourceURL = Bundle.main.resourceURL {
            let runtimeURL = resourceURL.appendingPathComponent("SharkTrackRuntime", isDirectory: true)
            let frozenExecutableURL = runtimeURL
                .appendingPathComponent("sharktrack-runner", isDirectory: true)
                .appendingPathComponent("sharktrack-runner")

            if FileManager.default.isExecutableFile(atPath: frozenExecutableURL.path) {
                return SharkTrackProcessor(runtime: try SharkTrackRuntime.appBundleExecutable())
            }

            if FileManager.default.fileExists(atPath: runtimeURL.path) {
                return SharkTrackProcessor(runtime: try SharkTrackRuntime.appBundleResource(named: "SharkTrackRuntime"))
            }
        }

        return SharkTrackProcessor()
    }
}

nonisolated struct SharkTrackMediaDiscovery: Sendable {
    enum MediaKind: Sendable {
        case video
        case image

        var fileExtensions: Set<String> {
            switch self {
            case .video:
                MediaFileExtensions.video
            case .image:
                MediaFileExtensions.sharkTrackImage
            }
        }
    }

    private let fileSystem: SharkTrackFileSystem
    private let generatedFolderNames: Set<String>

    init(
        fileManager: FileManager = .default,
        generatedFolderNames: Set<String> = GeneratedProjectArtifacts.folderNames
    ) {
        self.fileSystem = SharkTrackFileSystem(fileManager)
        self.generatedFolderNames = generatedFolderNames
    }

    static let `default` = SharkTrackMediaDiscovery()

    func mediaFiles(module: WorkflowModule, in root: URL) -> [URL] {
        let kind: MediaKind = module == .bruvVideo ? .video : .image
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        return (fileSystem.enumerator(at: root, includingPropertiesForKeys: keys)?
            .compactMap { $0 as? URL }
            .filter { isSupportedMediaFile($0, kind: kind, inputFolderURL: root, keys: keys) } ?? [])
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func isSupportedMediaFile(
        _ url: URL,
        kind: MediaKind,
        inputFolderURL: URL,
        keys: [URLResourceKey]
    ) -> Bool {
        guard kind.fileExtensions.contains(url.pathExtension.lowercased()),
              !isGeneratedProjectArtifact(url, inputFolderURL: inputFolderURL) else {
            return false
        }

        let values = try? url.resourceValues(forKeys: Set(keys))
        if values?.isRegularFile == true {
            return true
        }

        return values?.isSymbolicLink == true &&
            fileSystem.fileExists(atPath: url.resolvingSymlinksInPath().path)
    }

    private func isGeneratedProjectArtifact(_ url: URL, inputFolderURL: URL) -> Bool {
        let inputPath = inputFolderURL.standardizedFileURL.pathComponents
        let path = url.standardizedFileURL.pathComponents
        let relativeComponents = path.dropFirst(commonPrefixCount(inputPath, path))

        if inputFolderURL.lastPathComponent == ProjectFileNames.sourceDirectory,
           relativeComponents.first == ProjectFileNames.sourceDirectory {
            return false
        }

        return relativeComponents.contains { generatedFolderNames.contains($0.lowercased()) }
    }
}

nonisolated struct SharkTrackEventMapper {
    static func handle(
        _ event: SharkTrackEvent,
        fileURL: URL,
        collectedScreenshotCount: Int,
        onProgress: @Sendable (SharkTrackPreparationProgress) -> Void,
        onCompleted: (SharkTrackResult) -> Void
    ) {
        switch event {
        case .preparingRuntime:
            AppLog.sharkTrack("Preparing runtime for \(fileURL.lastPathComponent)")
        case .installingDependencies:
            AppLog.sharkTrack("Installing runtime dependencies")
        case .processingFile(let current, let total, let name):
            AppLog.sharkTrack("Runtime file progress \(current)/\(total): \(name)")
            onProgress(.processingFile(current: current, total: total, name: name))
        case .screenshotProcessed(let screenshot):
            AppLog.sharkTrack("Screenshot: \(screenshot.url.path)")
            onProgress(.processingDetection(collectedScreenshotCount + 1))
        case .processingProgress(let current, let total, let fraction, let elapsedSeconds, let remainingSeconds):
            logRuntimeProgress(
                current: current,
                total: total,
                fraction: fraction,
                elapsedSeconds: elapsedSeconds,
                remainingSeconds: remainingSeconds
            )
            onProgress(.processingProgress(
                current: current,
                total: total,
                fraction: fraction,
                elapsedSeconds: elapsedSeconds,
                remainingSeconds: remainingSeconds
            ))
        case .message(let message):
            AppLog.sharkTrack("Runtime message: \(message)")
        case .completed(let result):
            AppLog.sharkTrack("Runtime completed \(fileURL.lastPathComponent) with \(result.screenshots.count) screenshots")
            onCompleted(result)
            onProgress(.processingDetection(collectedScreenshotCount + result.screenshots.count))
        }
    }

    private static func logRuntimeProgress(
        current: Int,
        total: Int,
        fraction: Double,
        elapsedSeconds: TimeInterval,
        remainingSeconds: TimeInterval?
    ) {
        AppLog.sharkTrack(
            String(
                format: "Runtime progress %d/%d %.1f%% elapsed %.1fs remaining %@",
                current,
                total,
                fraction * 100,
                elapsedSeconds,
                remainingSeconds.map { String(format: "%.1fs", $0) } ?? "unknown"
            )
        )
    }
}

nonisolated struct SharkTrackResultAccumulator: Sendable {
    private let outputURL: URL
    private let processedFileCount: Int
    private var screenshots: [SharkTrackScreenshot] = []
    private var metadata: [String: String] = [:]
    private var duration: TimeInterval = 0

    var screenshotCount: Int {
        screenshots.count
    }

    init(outputURL: URL, processedFileCount: Int) {
        self.outputURL = outputURL
        self.processedFileCount = processedFileCount
    }

    mutating func append(_ result: SharkTrackResult) {
        screenshots.append(contentsOf: result.screenshots)
        metadata.merge(result.metadata) { _, new in new }
        duration += result.duration ?? 0
    }

    func result() -> SharkTrackResult {
        let uniqueScreenshots = Dictionary(grouping: screenshots, by: { $0.url.standardizedFileURL.path })
            .compactMap { $0.value.first }
            .sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }

        return SharkTrackResult(
            outputDirectory: outputURL,
            screenshots: uniqueScreenshots,
            processedFileCount: processedFileCount,
            duration: duration,
            metadata: metadata
        )
    }
}

nonisolated struct SharkTrackOutputWriter: Sendable {
    private let fileSystem: SharkTrackFileSystem

    init(fileManager: FileManager = .default) {
        self.fileSystem = SharkTrackFileSystem(fileManager)
    }

    static let `default` = SharkTrackOutputWriter()

    func writeDetections(
        from result: SharkTrackResult,
        module: WorkflowModule,
        outputURL: URL,
        projectRootURL: URL
    ) throws -> [SharkTrackDetectionOutput] {
        let outputs = try result.detections.map {
            try writeDetection($0, module: module, outputURL: outputURL, projectRootURL: projectRootURL)
        }
        return outputs.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    func writeDetection(
        _ detection: SharkTrackKit.SharkTrackDetection,
        module: WorkflowModule,
        outputURL: URL,
        projectRootURL: URL
    ) throws -> SharkTrackDetectionOutput {
        let destinationRoot = finalDetectionFolder(
            module: module,
            outputURL: outputURL,
            sourceFolderName: detection.sourceFolderName
        )
        try fileSystem.createDirectory(at: destinationRoot)

        let destinationURL = uniqueFileURL(for: detection.screenshotURL.lastPathComponent, in: destinationRoot)
        if detection.screenshotURL.standardizedFileURL != destinationURL.standardizedFileURL {
            if fileSystem.fileExists(atPath: destinationURL.path) {
                try fileSystem.removeItem(at: destinationURL)
            }
            try fileSystem.moveItem(at: detection.screenshotURL, to: destinationURL)
        }

        return SharkTrackDetectionOutput(
            fileURL: destinationURL,
            relativePath: RelativePath.url(destinationURL, relativeTo: projectRootURL),
            sourceVideoName: detection.sourceMediaName,
            trackID: detection.trackID,
            frameNumber: detection.reviewFrameNumber,
            maxN: detection.maxN,
            status: detection.status,
            timestamp: detection.timestamp,
            confidence: detection.confidence
        )
    }

    func finalDetectionFolder(module: WorkflowModule, outputURL: URL, sourceFolderName: String) -> URL {
        module == .bruvVideo
            ? outputURL.appendingPathComponent(sourceFolderName, isDirectory: true)
            : outputURL
    }

    func uniqueFileURL(for fileName: String, in folderURL: URL) -> URL {
        let original = URL(fileURLWithPath: fileName)
        let baseName = original.deletingPathExtension().lastPathComponent
        let pathExtension = original.pathExtension
        var candidate = folderURL.appendingPathComponent(fileName)
        var suffix = 1

        while fileSystem.fileExists(atPath: candidate.path) {
            let nextName = pathExtension.isEmpty
                ? "\(baseName)_\(suffix)"
                : "\(baseName)_\(suffix).\(pathExtension)"
            candidate = folderURL.appendingPathComponent(nextName)
            suffix += 1
        }

        return candidate
    }
}

nonisolated struct SharkTrackSummaryStore: Sendable {
    private let imageInspector: ImageInspector

    init(fileManager: FileManager = .default, imageInspector: ImageInspector = .default) {
        self.imageInspector = imageInspector
    }

    static let `default` = SharkTrackSummaryStore()

    func replaceFiles(
        at url: URL,
        with detections: [SharkTrackDetectionOutput],
        displayInputFolderURL: URL,
        wasSimulated: Bool
    ) throws {
        let data = try Data(contentsOf: url)
        var summary = try JSONDecoder.projectScan.decode(ProjectScanSummary.self, from: data)
        let sourceFiles = sourceFileIndex(summary.files)
        let detectionFiles = detections.map { scanFile(from: $0, sourceFiles: sourceFiles) }

        summary.fileCount = detectionFiles.count
        summary.readableFileCount = detectionFiles.count
        summary.unreadableFileCount = 0
        summary.files = detectionFiles
        summary.inputFolder = displayInputFolderURL.path
        summary.sharkTrackSimulated = wasSimulated

        let updatedData = try JSONEncoder.projectScan.encode(summary)
        try updatedData.write(to: url, options: .atomic)
    }

    private func sourceFileIndex(_ files: [ProjectScanFile]) -> [String: ProjectScanFile] {
        Dictionary(files.flatMap { file in
            [
                (file.fileName, file),
                (URL(fileURLWithPath: file.relativePath).lastPathComponent, file)
            ]
        }, uniquingKeysWith: { first, _ in first })
    }

    private func scanFile(
        from detection: SharkTrackDetectionOutput,
        sourceFiles: [String: ProjectScanFile]
    ) -> ProjectScanFile {
        let imageSize = imageInspector.size(of: detection.fileURL)
        let sourceFile = detection.sourceVideoName.flatMap { sourceFiles[$0] }
        return ProjectScanFile(
            fileName: detection.fileURL.lastPathComponent,
            relativePath: detection.relativePath,
            sizeBytes: fileSize(detection.fileURL),
            readable: true,
            readError: "",
            durationSeconds: detection.timestamp,
            sampleRateHz: nil,
            channels: nil,
            bitDepth: nil,
            format: "JPG",
            width: imageSize?.width,
            height: imageSize?.height,
            trackID: detection.trackID,
            frameNumber: detection.frameNumber,
            maxN: detection.maxN,
            sharkTrackConfidence: detection.confidence,
            frameCount: sourceFile?.frameCount,
            frameRate: sourceFile?.frameRate,
            sharkTrackStatus: detection.status,
            sharkTrackPreviewPath: detection.relativePath,
            sourceVideo: detection.sourceVideoName,
            clipStartSeconds: nil,
            clipDurationSeconds: nil,
            peakDBFS: nil,
            rmsDBFS: nil,
            clippingPercent: nil,
            nearZeroPercent: nil,
            qualityFlag: "OK",
            qualityReasons: []
        )
    }

    private func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }
}

nonisolated struct SharkTrackManifestStore: Sendable {
    var now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    static let `default` = SharkTrackManifestStore()

    func write(_ manifest: SharkTrackManifest, to url: URL) throws {
        var datedManifest = manifest
        datedManifest.updatedAt = now()
        let data = try JSONEncoder.projectScan.encode(datedManifest)
        try data.write(to: url, options: .atomic)
    }
}

nonisolated struct SharkTrackManifest: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case running
        case completed
    }

    var status: Status
    var moduleID: String
    var projectName: String
    var inputFolder: String
    var outputFolder: String
    var message: String
    var updatedAt: Date

    static func running(
        module: WorkflowModule,
        projectName: String,
        inputFolderURL: URL,
        outputFolderURL: URL,
        message: String
    ) -> SharkTrackManifest {
        SharkTrackManifest(
            status: .running,
            moduleID: module.id,
            projectName: projectName,
            inputFolder: inputFolderURL.path,
            outputFolder: outputFolderURL.path,
            message: message,
            updatedAt: Date()
        )
    }

    static func completed(
        module: WorkflowModule,
        projectName: String,
        inputFolderURL: URL,
        outputFolderURL: URL,
        detectionCount: Int,
        wasSimulated: Bool
    ) -> SharkTrackManifest {
        SharkTrackManifest(
            status: .completed,
            moduleID: module.id,
            projectName: projectName,
            inputFolder: inputFolderURL.path,
            outputFolder: outputFolderURL.path,
            message: String(
                format: wasSimulated
                    ? Strings.SharkTrackProgress.simulatedCompletedFormat
                    : Strings.SharkTrackProgress.completedFormat,
                detectionCount
            ),
            updatedAt: Date()
        )
    }

    enum CodingKeys: String, CodingKey {
        case status
        case moduleID = "module"
        case projectName = "project_name"
        case inputFolder = "input_folder"
        case outputFolder = "output_folder"
        case message
        case updatedAt = "updated_at"
    }
}

nonisolated struct ImageInspector: Sendable {
    var size: @Sendable (URL) -> (width: Int, height: Int)?

    static let `default` = ImageInspector { url in
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }

        return (width, height)
    }

    func size(of url: URL) -> (width: Int, height: Int)? {
        size(url)
    }
}

nonisolated struct SharkTrackFileSystem: @unchecked Sendable {
    private let fileManager: FileManager

    init(_ fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]) -> FileManager.DirectoryEnumerator? {
        fileManager.enumerator(at: url, includingPropertiesForKeys: keys)
    }
}

nonisolated struct RelativePath {
    static func url(_ url: URL, relativeTo rootURL: URL) -> String {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        let prefixCount = commonPrefixCount(rootComponents, fileComponents)
        guard prefixCount == rootComponents.count else {
            return url.lastPathComponent
        }

        return fileComponents.dropFirst(prefixCount).joined(separator: "/")
    }
}

nonisolated func commonPrefixCount(_ lhs: [String], _ rhs: [String]) -> Int {
    var count = 0
    for (left, right) in zip(lhs, rhs) {
        guard left == right else { break }
        count += 1
    }
    return count
}

nonisolated struct SharkTrackDetectionOutput: Sendable {
    let fileURL: URL
    let relativePath: String
    let sourceVideoName: String?
    let trackID: Int
    let frameNumber: Int?
    let maxN: Int?
    let status: String
    let timestamp: TimeInterval?
    let confidence: Double?
}
