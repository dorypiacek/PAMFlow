//
//  BRUVScanAnalyzer.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import AVFoundation
import UI
import Core
import Foundation
import ImageIO

/// Analyzes visual files discovered by the shared project scanner.
struct BRUVScanAnalyzer: ProjectScanAnalyzing {
    nonisolated private let analyzesVideo: Bool

    /// Creates an analyzer for either BRUV video or RUV image projects.
    init(projectType: BRUVProjectType) {
        analyzesVideo = projectType == .bruv
    }

    /// Reads visual metadata for one source file.
    nonisolated func analyzeFile(_ fileInfo: ProjectScanFileInfo) async -> ProjectScanFile {
        analyzesVideo
            ? await scanVideo(fileInfo)
            : scanImage(fileInfo)
    }

    /// Builds batch-level warnings from analyzed video or image files.
    nonisolated func warnings(files: [ProjectScanFile], totalSizeBytes: Int) -> [String] {
        var warnings: [String] = []
        if files.isEmpty {
            warnings.append(analyzesVideo ? BRUVStrings.ScanWarnings.noVideoFilesFound : BRUVStrings.ScanWarnings.noImageFilesFound)
        }
        if files.contains(where: { !$0.readable }) {
            warnings.append(BRUVStrings.ScanWarnings.unreadableFilesFound)
        }
        if Set(files.compactMap(\.format)).count > 1 {
            warnings.append(BRUVStrings.ScanWarnings.multipleFormatsFound)
        }
        if Set(files.compactMap({ file -> String? in
            guard let width = file.width, let height = file.height else { return nil }
            return "\(width)x\(height)"
        })).count > 1 {
            warnings.append(BRUVStrings.ScanWarnings.multipleResolutionsFound)
        }
        if files.contains(where: { $0.qualityReasons.contains("LOW_RESOLUTION") }) {
            warnings.append(BRUVStrings.ScanWarnings.lowResolutionFound)
        }
        if totalSizeBytes >= 10 * 1024 * 1024 * 1024 || files.count >= 500 {
            warnings.append(BRUVStrings.ScanWarnings.largeBatch)
        }
        return warnings
    }

    /// Builds visual-media summary attributes for the BRUV module.
    nonisolated func summaryAttributes(files: [ProjectScanFile]) -> [String: ScanAttributeValue] {
        let readableFiles = files.filter(\.readable)
        let frameCounts = readableFiles.compactMap { $0.frameCount }
        let resolutions = readableFiles.compactMap { file -> String? in
            guard let width = file.width, let height = file.height else { return nil }
            return "\(width)x\(height)"
        }
        var attributes: [String: ScanAttributeValue] = [
            BRUVScanAttribute.resolutions: .strings(sortedUniqueStrings(resolutions))
        ]
        if let min = frameCounts.min() {
            attributes[BRUVScanAttribute.frameCountMin] = .int(min)
        }
        if let max = frameCounts.max() {
            attributes[BRUVScanAttribute.frameCountMax] = .int(max)
        }
        return attributes
    }

    nonisolated private func sortedUniqueStrings(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    /// Reads image dimensions and creates a scan record for one RUV source file.
    nonisolated private func scanImage(_ fileInfo: ProjectScanFileInfo) -> ProjectScanFile {
        guard
            let source = CGImageSourceCreateWithURL(fileInfo.url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return ProjectScanFileFactory.unreadableFile(fileInfo, message: BRUVStrings.ScanWarnings.imageMetadataUnreadable)
        }

        let reasons = imageQualityReasons(width: width, height: height, sizeBytes: fileInfo.sizeBytes)
        return ProjectScanFile(
            fileName: fileInfo.fileName,
            relativePath: fileInfo.relativePath,
            sizeBytes: fileInfo.sizeBytes,
            readable: true,
            readError: "",
            durationSeconds: nil,
            format: fileInfo.format,
            qualityFlag: reasons.isEmpty ? ProjectQuality.ok : ProjectQuality.check,
            qualityReasons: reasons,
            attributes: [
                BRUVScanAttribute.width: .int(width),
                BRUVScanAttribute.height: .int(height),
                BRUVScanAttribute.frameNumber: .int(1),
                BRUVScanAttribute.frameCount: .int(1),
                BRUVScanAttribute.status: .string(ProjectScanStatus.pending)
            ]
        )
    }

    /// Reads video duration, dimensions, frame rate, and estimated frame count for one BRUV source file.
    nonisolated private func scanVideo(_ fileInfo: ProjectScanFileInfo) async -> ProjectScanFile {
        let asset = AVURLAsset(url: fileInfo.url)

        let durationSeconds: Double
        let videoTrack: AVAssetTrack
        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            durationSeconds = CMTimeGetSeconds(duration)
            guard let firstVideoTrack = tracks.first else {
                return ProjectScanFileFactory.unreadableFile(fileInfo, message: BRUVStrings.ScanWarnings.videoTrackUnreadable)
            }
            videoTrack = firstVideoTrack
        } catch {
            return ProjectScanFileFactory.unreadableFile(fileInfo, message: error.localizedDescription)
        }

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return ProjectScanFileFactory.unreadableFile(fileInfo, message: BRUVStrings.ScanWarnings.videoMetadataUnreadable)
        }

        do {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
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
                sizeBytes: fileInfo.sizeBytes
            )

            return ProjectScanFile(
                fileName: fileInfo.fileName,
                relativePath: fileInfo.relativePath,
                sizeBytes: fileInfo.sizeBytes,
                readable: true,
                readError: "",
                durationSeconds: durationSeconds,
                format: fileInfo.format,
                qualityFlag: reasons.isEmpty ? ProjectQuality.ok : ProjectQuality.check,
                qualityReasons: reasons,
                attributes: [
                    BRUVScanAttribute.width: .int(width),
                    BRUVScanAttribute.height: .int(height),
                    BRUVScanAttribute.status: .string(ProjectScanStatus.pending)
                ]
                .merging(frameCount.map { [BRUVScanAttribute.frameCount: .int($0)] } ?? [:]) { current, _ in current }
                .merging(frameRate > 0 ? [BRUVScanAttribute.frameRate: .double(frameRate)] : [:]) { current, _ in current }
            )
        } catch {
            return ProjectScanFileFactory.unreadableFile(fileInfo, message: error.localizedDescription)
        }
    }

    /// Converts image metadata into persisted quality reason codes.
    nonisolated private func imageQualityReasons(width: Int, height: Int, sizeBytes: Int) -> [String] {
        var reasons: [String] = []
        if width <= 0 || height <= 0 { reasons.append("BAD_RESOLUTION") }
        if width < 640 || height < 480 { reasons.append("LOW_RESOLUTION") }
        if sizeBytes == 0 { reasons.append("EMPTY_FILE") }
        return reasons
    }

    /// Converts video metadata into persisted quality reason codes.
    nonisolated private func videoQualityReasons(
        durationSeconds: Double,
        width: Int,
        height: Int,
        frameRate: Double,
        frameCount: Int?,
        sizeBytes: Int
    ) -> [String] {
        var reasons: [String] = []
        if durationSeconds <= 0 { reasons.append("BAD_DURATION") }
        if width <= 0 || height <= 0 { reasons.append("BAD_RESOLUTION") }
        if width < 640 || height < 480 { reasons.append("LOW_RESOLUTION") }
        if frameRate <= 0 { reasons.append("UNKNOWN_FRAME_RATE") }
        if frameCount == nil || frameCount == 0 { reasons.append("NO_FRAMES_ESTIMATED") }
        if sizeBytes == 0 { reasons.append("EMPTY_FILE") }
        return reasons
    }
}
