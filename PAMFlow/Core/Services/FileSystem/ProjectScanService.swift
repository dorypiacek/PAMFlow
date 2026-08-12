//
//  ProjectScanService.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Scan operations and summary loading used across processing and overview screens.
@MainActor
protocol ProjectScanServicing {
    func scan(
        project: Project,
        onProgress: @escaping @Sendable (ProjectScanService.Progress) -> Void
    ) async throws -> ProjectScanSummary

    func loadSummary(for project: Project) throws -> ProjectScanSummary
}

/// Runs the technical scan step and loads its summary output.
///
/// The service owns the temporary `work/recording_summary.json` contract for
/// processing services. The durable copy lives on the Project model so overview
/// and exports can still work when a project folder is unavailable.
final class ProjectScanService: ProjectScanServicing {
    /// User-visible scan progress emitted by the scanner process.
    struct Progress: Sendable {
        let currentFileIndex: Int?
        let totalFileCount: Int?
        let currentFile: String?
        let message: String

        var fractionCompleted: Double? {
            guard
                let currentFileIndex,
                let totalFileCount,
                totalFileCount > 0
            else {
                return nil
            }

            return min(Double(currentFileIndex) / Double(totalFileCount), 1)
        }
    }

    enum ProjectScanError: LocalizedError {
        case missingProjectFolder
        case missingInputFolder
        case missingSummary(URL)

        var errorDescription: String? {
            switch self {
            case .missingProjectFolder:
                Strings.ProjectScan.missingProjectFolder
            case .missingInputFolder:
                Strings.ProjectScan.missingInputFolder
            case .missingSummary(let url):
                String(format: Strings.ProjectScan.missingSummaryFormat, url.path)
            }
        }
    }

    /// Scans a project's input folder and returns the parsed summary.
    func scan(
        project: Project,
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> ProjectScanSummary {
        AppLog.info("Starting scan for project '\(project.name)' (\(project.id.uuidString))")
        guard let projectRootURL = project.rootFolderURL else {
            AppLog.info("Scan failed before start: missing project folder bookmark")
            throw ProjectScanError.missingProjectFolder
        }

        guard let inputFolderURL = project.inputFolderURL else {
            AppLog.info("Scan failed before start: missing input folder bookmark")
            throw ProjectScanError.missingInputFolder
        }
        let displayInputFolderURL = project.rawInputFolderURL ?? inputFolderURL

        AppLog.info("Resolved project root: \(projectRootURL.path)")
        AppLog.info("Resolved input folder: \(inputFolderURL.path)")
        AppLog.info("Resolved raw input folder: \(displayInputFolderURL.path)")

        let module = WorkflowModule.module(for: project.moduleID)
        let summary = try await Task.detached {
            try await self.scanMediaData(
                module: module,
                projectRootURL: projectRootURL,
                inputFolderURL: inputFolderURL,
                displayInputFolderURL: displayInputFolderURL,
                recorderID: project.metadataOpcode ?? "",
                onProgress: onProgress
            )
        }.value

        AppLog.info("Scan decoded summary: \(summary.fileCount) files, \(summary.qualityWarningCount) warnings")
        return summary
    }

    /// Loads the scan summary that was previously written into the project work folder.
    func loadSummary(for project: Project) throws -> ProjectScanSummary {
        AppLog.info("Loading scan summary for project '\(project.name)'")
        let loadedSummaryData: Data
        if let projectRootURL = project.rootFolderURL,
           let fileSummaryData = try? summaryData(projectRootURL: projectRootURL) {
            loadedSummaryData = fileSummaryData
        } else if let storedSummaryData = project.scanSummaryData {
            AppLog.scan("Using SwiftData scan summary snapshot for project '\(project.name)'")
            loadedSummaryData = storedSummaryData
        } else if project.rootFolderURL == nil {
            AppLog.info("Summary load failed: missing project folder bookmark and no SwiftData snapshot")
            throw ProjectScanError.missingProjectFolder
        } else {
            let summaryURL = project.rootFolderURL?
                .appendingPathComponent(ProjectFileNames.workDirectory)
                .appendingPathComponent(ProjectFileNames.scanSummary) ?? URL(fileURLWithPath: ProjectFileNames.scanSummary)
            AppLog.scan("Missing summary at \(summaryURL.path) and no SwiftData snapshot")
            throw ProjectScanError.missingSummary(summaryURL)
        }

        let summary = try decodeSummary(from: loadedSummaryData)
        AppLog.info("Loaded scan summary: \(summary.fileCount) files")
        return summary
    }

    nonisolated private func summaryData(projectRootURL: URL) throws -> Data {
        let accessedProject = projectRootURL.startAccessingSecurityScopedResource()
        AppLog.scan("Reading summary with project security scope=\(accessedProject)")
        defer {
            if accessedProject {
                projectRootURL.stopAccessingSecurityScopedResource()
            }
        }

        let rootSummaryURL = projectRootURL
            .appendingPathComponent(ProjectFileNames.scanSummary)
        let workSummaryURL = projectRootURL
            .appendingPathComponent(ProjectFileNames.workDirectory)
            .appendingPathComponent(ProjectFileNames.scanSummary)
        let summaryURL = FileManager.default.fileExists(atPath: workSummaryURL.path)
            ? workSummaryURL
            : rootSummaryURL

        guard FileManager.default.fileExists(atPath: summaryURL.path) else {
            AppLog.scan("Missing summary at \(summaryURL.path)")
            throw ProjectScanError.missingSummary(summaryURL)
        }

        AppLog.scan("Found summary at \(summaryURL.path)")
        return try Data(contentsOf: summaryURL)
    }

    nonisolated private func scanMediaData(
        module: WorkflowModule,
        projectRootURL: URL,
        inputFolderURL: URL,
        displayInputFolderURL: URL,
        recorderID: String,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> ProjectScanSummary {
        let accessedProject = projectRootURL.startAccessingSecurityScopedResource()
        let accessedInput = inputFolderURL.startAccessingSecurityScopedResource()
        AppLog.scan("Native media scan security scope project=\(accessedProject) input=\(accessedInput)")

        defer {
            if accessedProject {
                projectRootURL.stopAccessingSecurityScopedResource()
            }

            if accessedInput {
                inputFolderURL.stopAccessingSecurityScopedResource()
            }
        }

        let mediaURLs = try supportedMediaURLs(in: inputFolderURL, module: module)
        onProgress(Progress(
            currentFileIndex: mediaURLs.isEmpty ? 0 : nil,
            totalFileCount: mediaURLs.count,
            currentFile: nil,
            message: mediaURLs.isEmpty
                ? Strings.ProjectScan.noSupportedFilesFound
                : String(format: Strings.ProjectScan.supportedFilesFoundFormat, mediaURLs.count)
        ))

        var files: [ProjectScanFile] = []
        for (offset, url) in mediaURLs.enumerated() {
            let index = offset + 1
            let relativePath = relativePath(for: url, inputFolderURL: inputFolderURL)
            AppLog.scan("Scanning file \(index)/\(mediaURLs.count): \(relativePath)")
            onProgress(Progress(
                currentFileIndex: index,
                totalFileCount: mediaURLs.count,
                currentFile: relativePath,
                message: String(format: Strings.ProjectScan.scanningFileFormat, index, mediaURLs.count)
            ))

            let file: ProjectScanFile
            switch module {
            case .pamAudio:
                file = scanAudio(url: url, inputFolderURL: inputFolderURL)
            case .bruvVideo:
                file = await scanVideo(url: url, inputFolderURL: inputFolderURL)
            case .ruvImages:
                file = scanImage(url: url, inputFolderURL: inputFolderURL)
            }
            files.append(file)
        }

        let summary = buildMediaSummary(
            projectRootURL: projectRootURL,
            inputFolderURL: inputFolderURL,
            displayInputFolderURL: displayInputFolderURL,
            recorderID: recorderID,
            module: module,
            files: files
        )
        try Self.writeSummary(summary, projectRootURL: projectRootURL)
        AppLog.scan("Native media scan complete")
        return summary
    }

    nonisolated private func scanAudio(url: URL, inputFolderURL: URL) -> ProjectScanFile {
        let sizeBytes = fileSize(url)
        let relativePath = relativePath(for: url, inputFolderURL: inputFolderURL)

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let sampleRate = format.sampleRate
            let channelCount = Int(format.channelCount)
            let durationSeconds = sampleRate > 0 ? Double(audioFile.length) / sampleRate : nil
            let bitDepth = (audioFile.fileFormat.settings[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue

            let metrics = try audioLevelMetrics(audioFile: audioFile, format: format)
            let reasons = audioQualityReasons(
                durationSeconds: durationSeconds,
                sizeBytes: sizeBytes,
                peak: metrics.peak,
                clippingPercent: metrics.clippingPercent,
                nearZeroPercent: metrics.nearZeroPercent,
                rms: metrics.rms
            )

            return ProjectScanFile(
                fileName: url.lastPathComponent,
                relativePath: relativePath,
                sizeBytes: sizeBytes,
                readable: true,
                readError: "",
                durationSeconds: durationSeconds,
                sampleRateHz: Int(sampleRate.rounded()),
                channels: channelCount,
                bitDepth: bitDepth,
                format: url.pathExtension.uppercased(),
                width: nil,
                height: nil,
                frameNumber: nil,
                maxN: nil,
                frameCount: nil,
                frameRate: nil,
                sharkTrackStatus: nil,
                sharkTrackPreviewPath: nil,
                peakDBFS: decibelsFullScale(metrics.peak),
                rmsDBFS: decibelsFullScale(metrics.rms),
                clippingPercent: metrics.clippingPercent,
                nearZeroPercent: metrics.nearZeroPercent,
                qualityFlag: reasons.isEmpty ? "OK" : "CHECK",
                qualityReasons: reasons
            )
        } catch {
            return mediaErrorFile(url: url, inputFolderURL: inputFolderURL, message: error.localizedDescription)
        }
    }

    nonisolated private func supportedMediaURLs(in inputFolderURL: URL, module: WorkflowModule) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: inputFolderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let extensions = module.supportedFileExtensions
        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                let values = try? url.resourceValues(forKeys: resourceKeys)
                let isSupportedFile = values?.isRegularFile == true ||
                    (values?.isSymbolicLink == true && FileManager.default.fileExists(atPath: url.resolvingSymlinksInPath().path))
                return isSupportedFile &&
                    extensions.contains(url.pathExtension.lowercased()) &&
                    !isGeneratedProjectArtifact(url, inputFolderURL: inputFolderURL)
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    nonisolated private func isGeneratedProjectArtifact(_ url: URL, inputFolderURL: URL) -> Bool {
        let generatedFolders = GeneratedProjectArtifacts.folderNames
        let inputFolderPath = inputFolderURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        let inputFolderIsProjectSource = inputFolderURL.lastPathComponent == ProjectFileNames.sourceDirectory
        return url.pathComponents.contains { component in
            if inputFolderIsProjectSource,
               component == ProjectFileNames.sourceDirectory,
               urlPath.hasPrefix(inputFolderPath + "/") {
                return false
            }
            return generatedFolders.contains(component.lowercased())
        }
    }

    nonisolated private func scanImage(url: URL, inputFolderURL: URL) -> ProjectScanFile {
        let sizeBytes = fileSize(url)
        let relativePath = relativePath(for: url, inputFolderURL: inputFolderURL)
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return mediaErrorFile(url: url, inputFolderURL: inputFolderURL, message: Strings.ProjectScan.imageMetadataUnreadable)
        }

        let reasons = imageQualityReasons(width: width, height: height, sizeBytes: sizeBytes)
        return ProjectScanFile(
            fileName: url.lastPathComponent,
            relativePath: relativePath,
            sizeBytes: sizeBytes,
            readable: true,
            readError: "",
            durationSeconds: nil,
            sampleRateHz: nil,
            channels: nil,
            bitDepth: nil,
            format: url.pathExtension.uppercased(),
            width: width,
            height: height,
            frameNumber: 1,
            maxN: nil,
            frameCount: 1,
            frameRate: nil,
            sharkTrackStatus: ProjectScanStatus.pending,
            sharkTrackPreviewPath: nil,
            peakDBFS: nil,
            rmsDBFS: nil,
            clippingPercent: nil,
            nearZeroPercent: nil,
            qualityFlag: reasons.isEmpty ? "OK" : "CHECK",
            qualityReasons: reasons
        )
    }

    nonisolated private func scanVideo(url: URL, inputFolderURL: URL) async -> ProjectScanFile {
        let sizeBytes = fileSize(url)
        let relativePath = relativePath(for: url, inputFolderURL: inputFolderURL)
        let asset = AVURLAsset(url: url)

        let durationSeconds: Double
        let videoTrack: AVAssetTrack
        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            durationSeconds = CMTimeGetSeconds(duration)
            guard let firstVideoTrack = tracks.first else {
                return mediaErrorFile(url: url, inputFolderURL: inputFolderURL, message: Strings.ProjectScan.videoTrackUnreadable)
            }
            videoTrack = firstVideoTrack
        } catch {
            return mediaErrorFile(url: url, inputFolderURL: inputFolderURL, message: error.localizedDescription)
        }

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return mediaErrorFile(url: url, inputFolderURL: inputFolderURL, message: Strings.ProjectScan.videoMetadataUnreadable)
        }

        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let nominalFrameRate: Float
        do {
            naturalSize = try await videoTrack.load(.naturalSize)
            preferredTransform = try await videoTrack.load(.preferredTransform)
            nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        } catch {
            return mediaErrorFile(url: url, inputFolderURL: inputFolderURL, message: error.localizedDescription)
        }

        let transformedSize = naturalSize.applying(preferredTransform)
        let width = Int(abs(transformedSize.width).rounded())
        let height = Int(abs(transformedSize.height).rounded())
        let frameRate = Double(nominalFrameRate)
        let frameCount = frameRate > 0 ? Int((durationSeconds * frameRate).rounded()) : nil
        let reasons = videoQualityReasons(
            durationSeconds: durationSeconds,
            width: width,
            height: height,
            frameRate: frameRate,
            frameCount: frameCount,
            sizeBytes: sizeBytes
        )

        return ProjectScanFile(
            fileName: url.lastPathComponent,
            relativePath: relativePath,
            sizeBytes: sizeBytes,
            readable: true,
            readError: "",
            durationSeconds: durationSeconds,
            sampleRateHz: nil,
            channels: nil,
            bitDepth: nil,
            format: url.pathExtension.uppercased(),
            width: width,
            height: height,
            frameNumber: nil,
            maxN: nil,
            frameCount: frameCount,
            frameRate: frameRate > 0 ? frameRate : nil,
            sharkTrackStatus: ProjectScanStatus.pending,
            sharkTrackPreviewPath: nil,
            peakDBFS: nil,
            rmsDBFS: nil,
            clippingPercent: nil,
            nearZeroPercent: nil,
            qualityFlag: reasons.isEmpty ? "OK" : "CHECK",
            qualityReasons: reasons
        )
    }

    nonisolated private func mediaErrorFile(
        url: URL,
        inputFolderURL: URL,
        message: String
    ) -> ProjectScanFile {
        ProjectScanFile(
            fileName: url.lastPathComponent,
            relativePath: relativePath(for: url, inputFolderURL: inputFolderURL),
            sizeBytes: fileSize(url),
            readable: false,
            readError: message,
            durationSeconds: nil,
            sampleRateHz: nil,
            channels: nil,
            bitDepth: nil,
            format: url.pathExtension.uppercased(),
            width: nil,
            height: nil,
            frameNumber: nil,
            maxN: nil,
            frameCount: nil,
            frameRate: nil,
            sharkTrackStatus: ProjectScanStatus.unavailable,
            sharkTrackPreviewPath: nil,
            peakDBFS: nil,
            rmsDBFS: nil,
            clippingPercent: nil,
            nearZeroPercent: nil,
            qualityFlag: ProjectQuality.check,
            qualityReasons: [ProjectQuality.readError]
        )
    }

    nonisolated private func buildMediaSummary(
        projectRootURL: URL,
        inputFolderURL: URL,
        displayInputFolderURL: URL,
        recorderID: String,
        module: WorkflowModule,
        files: [ProjectScanFile]
    ) -> ProjectScanSummary {
        let readableFiles = files.filter(\.readable)
        let durations = readableFiles.compactMap(\.durationSeconds)
        let frameCounts = readableFiles.compactMap(\.frameCount)
        let totalSizeBytes = files.reduce(0) { $0 + $1.sizeBytes }
        let warnings = mediaWarnings(files: files, module: module, totalSizeBytes: totalSizeBytes)

        return ProjectScanSummary(
            projectName: projectRootURL.lastPathComponent,
            recorderID: recorderID,
            inputFolder: displayInputFolderURL.path,
            scannedAt: .now,
            fileCount: files.count,
            readableFileCount: readableFiles.count,
            unreadableFileCount: files.count - readableFiles.count,
            totalSizeBytes: totalSizeBytes,
            durationMinSeconds: durations.min(),
            durationMaxSeconds: durations.max(),
            durationModeSeconds: roundMostCommon(durations),
            sampleRatesHz: sortedUniqueInts(readableFiles.compactMap(\.sampleRateHz)),
            channelCounts: sortedUniqueInts(readableFiles.compactMap(\.channels)),
            bitDepths: sortedUniqueInts(readableFiles.compactMap(\.bitDepth)),
            formats: sortedUnique(readableFiles.compactMap(\.format)),
            resolutions: sortedUnique(readableFiles.compactMap { file in
                guard let width = file.width, let height = file.height else { return nil }
                return "\(width)x\(height)"
            }),
            frameCountMin: frameCounts.min(),
            frameCountMax: frameCounts.max(),
            qualityWarningCount: files.filter { $0.qualityFlag != "OK" }.count,
            warnings: warnings,
            files: files
        )
    }

    nonisolated static func writeSummary(_ summary: ProjectScanSummary, projectRootURL: URL) throws {
        let workURL = projectRootURL.appendingPathComponent(ProjectFileNames.workDirectory)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(
            withJSONObject: summaryJSON(summary),
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: workURL.appendingPathComponent(ProjectFileNames.scanSummary), options: .atomic)
    }

    nonisolated static func encodedSummaryData(_ summary: ProjectScanSummary) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: summaryJSON(summary),
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    nonisolated private static func summaryJSON(_ summary: ProjectScanSummary) -> [String: Any] {
        var json: [String: Any] = [
            "project_name": summary.projectName,
            "recorder_id": summary.recorderID ?? "",
            "input_folder": summary.inputFolder,
            "file_count": summary.fileCount,
            "readable_file_count": summary.readableFileCount,
            "unreadable_file_count": summary.unreadableFileCount,
            "total_size_bytes": summary.totalSizeBytes,
            "sample_rates_hz": summary.sampleRatesHz,
            "channel_counts": summary.channelCounts,
            "bit_depths": summary.bitDepths,
            "quality_warning_count": summary.qualityWarningCount,
            "warnings": summary.warnings,
            "files": summary.files.map(fileJSON)
        ]

        if let scannedAt = summary.scannedAt {
            json["scanned_at"] = ISO8601DateFormatter().string(from: scannedAt)
        }
        if let durationMinSeconds = summary.durationMinSeconds {
            json["duration_min_seconds"] = durationMinSeconds
        }
        if let durationMaxSeconds = summary.durationMaxSeconds {
            json["duration_max_seconds"] = durationMaxSeconds
        }
        if let durationModeSeconds = summary.durationModeSeconds {
            json["duration_mode_seconds"] = durationModeSeconds
        }
        json["formats"] = summary.formats ?? []
        json["resolutions"] = summary.resolutions ?? []
        if let frameCountMin = summary.frameCountMin {
            json["frame_count_min"] = frameCountMin
        }
        if let frameCountMax = summary.frameCountMax {
            json["frame_count_max"] = frameCountMax
        }
        return json
    }

    nonisolated private static func fileJSON(_ file: ProjectScanFile) -> [String: Any] {
        var json: [String: Any] = [
            "file_name": file.fileName,
            "relative_path": file.relativePath,
            "size_bytes": file.sizeBytes,
            "readable": file.readable,
            "read_error": file.readError,
            "quality_flag": file.qualityFlag,
            "quality_reasons": file.qualityReasons
        ]

        if let durationSeconds = file.durationSeconds {
            json["duration_seconds"] = durationSeconds
        }
        if let sampleRateHz = file.sampleRateHz {
            json["sample_rate_hz"] = sampleRateHz
        }
        if let channels = file.channels {
            json["channels"] = channels
        }
        if let bitDepth = file.bitDepth {
            json["bit_depth"] = bitDepth
        }
        if let format = file.format {
            json["format"] = format
        }
        if let width = file.width {
            json["width"] = width
        }
        if let height = file.height {
            json["height"] = height
        }
        if let frameNumber = file.frameNumber {
            json["frame_number"] = frameNumber
        }
        if let maxN = file.maxN {
            json["max_n"] = maxN
        }
        if let frameCount = file.frameCount {
            json["frame_count"] = frameCount
        }
        if let frameRate = file.frameRate {
            json["frame_rate"] = frameRate
        }
        if let sharkTrackStatus = file.sharkTrackStatus {
            json["sharktrack_status"] = sharkTrackStatus
        }
        if let sharkTrackPreviewPath = file.sharkTrackPreviewPath {
            json["sharktrack_preview_path"] = sharkTrackPreviewPath
        }
        if let sourceVideo = file.sourceVideo {
            json["source_video"] = sourceVideo
        }
        if let peakDBFS = file.peakDBFS {
            json["peak_dbfs"] = peakDBFS
        }
        if let rmsDBFS = file.rmsDBFS {
            json["rms_dbfs"] = rmsDBFS
        }
        if let clippingPercent = file.clippingPercent {
            json["clipping_percent"] = clippingPercent
        }
        if let nearZeroPercent = file.nearZeroPercent {
            json["near_zero_percent"] = nearZeroPercent
        }
        return json
    }

    private func decodeSummary(from data: Data) throws -> ProjectScanSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var summary = try decoder.decode(ProjectScanSummary.self, from: data)

        // Repair older SharkTrack summaries without conflating the source
        // video's frame number with the tracked individual's identifier.
        summary.files = summary.files.map { file in
            var migrated = file
            if migrated.sharkTrackStatus != nil {
                let artifactName = URL(fileURLWithPath: migrated.relativePath)
                    .deletingPathExtension().lastPathComponent
                if let artifactTrackID = Int(artifactName.split(separator: "-").first ?? "") {
                    migrated.trackID = artifactTrackID
                }
                migrated.maxN = nil
            }
            return migrated
        }
        return summary
    }

    nonisolated private func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            let targetValues = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey])
            if let targetSize = targetValues?.fileSize {
                return targetSize
            }
        }

        return values?.fileSize ?? 0
    }

    nonisolated private func relativePath(for url: URL, inputFolderURL: URL) -> String {
        let inputPath = inputFolderURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(inputPath) else {
            return url.lastPathComponent
        }

        return String(filePath.dropFirst(inputPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    nonisolated private func imageQualityReasons(width: Int, height: Int, sizeBytes: Int) -> [String] {
        var reasons: [String] = []
        if width <= 0 || height <= 0 {
            reasons.append("BAD_RESOLUTION")
        }
        if width < 640 || height < 480 {
            reasons.append("LOW_RESOLUTION")
        }
        if sizeBytes == 0 {
            reasons.append("EMPTY_FILE")
        }
        return reasons
    }

    nonisolated private func videoQualityReasons(
        durationSeconds: Double,
        width: Int,
        height: Int,
        frameRate: Double,
        frameCount: Int?,
        sizeBytes: Int
    ) -> [String] {
        var reasons: [String] = []
        if durationSeconds <= 0 {
            reasons.append("BAD_DURATION")
        }
        if width <= 0 || height <= 0 {
            reasons.append("BAD_RESOLUTION")
        }
        if width < 640 || height < 480 {
            reasons.append("LOW_RESOLUTION")
        }
        if frameRate <= 0 {
            reasons.append("UNKNOWN_FRAME_RATE")
        }
        if frameCount == nil || frameCount == 0 {
            reasons.append("NO_FRAMES_ESTIMATED")
        }
        if sizeBytes == 0 {
            reasons.append("EMPTY_FILE")
        }
        return reasons
    }

    nonisolated private func audioLevelMetrics(
        audioFile: AVAudioFile,
        format: AVAudioFormat
    ) throws -> AudioLevelMetrics {
        let frameCapacity = AVAudioFrameCount(262_144)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        audioFile.framePosition = 0
        let channelCount = max(Int(format.channelCount), 1)
        var sampleCount = 0
        var peak = 0.0
        var sumSquares = 0.0
        var clippingCount = 0
        var nearZeroCount = 0
        let clippingThreshold = 0.999
        let nearZeroThreshold = 1.0 / 32_768.0

        while audioFile.framePosition < audioFile.length {
            let remainingFrames = audioFile.length - audioFile.framePosition
            let framesToRead = AVAudioFrameCount(min(Int64(frameCapacity), remainingFrames))
            try audioFile.read(into: buffer, frameCount: framesToRead)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }

            guard let channelData = buffer.floatChannelData else {
                throw CocoaError(.fileReadCorruptFile)
            }

            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameLength {
                    let absoluteSample = abs(Double(samples[frame]))
                    peak = max(peak, absoluteSample)
                    sumSquares += absoluteSample * absoluteSample
                    sampleCount += 1

                    if absoluteSample >= clippingThreshold {
                        clippingCount += 1
                    }

                    if absoluteSample <= nearZeroThreshold {
                        nearZeroCount += 1
                    }
                }
            }
        }

        guard sampleCount > 0 else {
            return AudioLevelMetrics(peak: 0, rms: 0, clippingPercent: 0, nearZeroPercent: 100)
        }

        return AudioLevelMetrics(
            peak: peak,
            rms: sqrt(sumSquares / Double(sampleCount)),
            clippingPercent: Double(clippingCount) / Double(sampleCount) * 100,
            nearZeroPercent: Double(nearZeroCount) / Double(sampleCount) * 100
        )
    }

    nonisolated private func audioQualityReasons(
        durationSeconds: Double?,
        sizeBytes: Int,
        peak: Double,
        clippingPercent: Double,
        nearZeroPercent: Double,
        rms: Double
    ) -> [String] {
        var reasons: [String] = []
        if durationSeconds == nil || durationSeconds == 0 {
            reasons.append("BAD_DURATION")
        }
        if sizeBytes == 0 {
            reasons.append("EMPTY_FILE")
        }
        if peak >= 0.999 {
            reasons.append("CLIPPING_OR_NEAR_CLIPPING")
        }
        if clippingPercent >= 0.01 {
            reasons.append("MANY_CLIPPED_SAMPLES")
        }
        if rms <= 0.0001 {
            reasons.append("VERY_LOW_LEVEL")
        }
        if nearZeroPercent >= 95 {
            reasons.append("MOSTLY_NEAR_ZERO")
        }
        return reasons
    }

    nonisolated private func decibelsFullScale(_ normalizedLevel: Double) -> Double {
        guard normalizedLevel > 0 else { return -120 }
        return 20 * log10(normalizedLevel)
    }

    nonisolated private func mediaWarnings(
        files: [ProjectScanFile],
        module: WorkflowModule,
        totalSizeBytes: Int
    ) -> [String] {
        var warnings: [String] = []
        if files.isEmpty {
            switch module {
            case .pamAudio:
                warnings.append(Strings.ProjectScan.noWAVFilesFound)
            case .bruvVideo:
                warnings.append(Strings.ProjectScan.noVideoFilesFound)
            case .ruvImages:
                warnings.append(Strings.ProjectScan.noImageFilesFound)
            }
        }
        if files.contains(where: { !$0.readable }) {
            warnings.append(Strings.ProjectScan.unreadableFilesFound)
        }
        if module == .pamAudio, Set(files.compactMap(\.sampleRateHz)).count > 1 {
            warnings.append(Strings.ProjectScan.multipleSampleRatesFound)
        }
        if module == .pamAudio, files.contains(where: { $0.qualityReasons.contains("CLIPPING_OR_NEAR_CLIPPING") || $0.qualityReasons.contains("MANY_CLIPPED_SAMPLES") }) {
            warnings.append(Strings.ProjectScan.clippedFilesFound)
        }
        if module == .pamAudio, files.contains(where: { $0.qualityReasons.contains("MOSTLY_NEAR_ZERO") || $0.qualityReasons.contains("VERY_LOW_LEVEL") }) {
            warnings.append(Strings.ProjectScan.nearlyEmptyFilesFound)
        }
        if module != .pamAudio, Set(files.compactMap(\.format)).count > 1 {
            warnings.append("Multiple file formats found.")
        }
        if module != .pamAudio, Set(files.compactMap { file -> String? in
            guard let width = file.width, let height = file.height else { return nil }
            return "\(width)x\(height)"
        }).count > 1 {
            warnings.append("Multiple resolutions found.")
        }
        if module != .pamAudio, files.contains(where: { $0.qualityReasons.contains("LOW_RESOLUTION") }) {
            warnings.append("Some files have low resolution.")
        }
        if totalSizeBytes >= 10 * 1024 * 1024 * 1024 || files.count >= 500 {
            warnings.append("This batch is large and may take a while.")
        }
        return warnings
    }

    nonisolated private func roundMostCommon(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var counts: [Double: Int] = [:]
        for value in values {
            let rounded = value.rounded()
            counts[rounded, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    nonisolated private func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    nonisolated private func sortedUniqueInts(_ values: [Int]) -> [Int] {
        Array(Set(values)).sorted()
    }
}

nonisolated private struct AudioLevelMetrics: Sendable {
    let peak: Double
    let rms: Double
    let clippingPercent: Double
    let nearZeroPercent: Double
}
