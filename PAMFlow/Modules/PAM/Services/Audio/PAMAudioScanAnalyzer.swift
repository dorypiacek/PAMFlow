//
//  PAMAudioScanAnalyzer.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import AVFoundation
import Foundation

/// Analyzes PAM audio files discovered by the shared project scanner.
struct PAMAudioScanAnalyzer: ProjectScanAnalyzing {
    /// Reads audio metadata and level metrics for one source file.
    nonisolated func analyzeFile(_ fileInfo: ProjectScanFileInfo) async -> ProjectScanFile {
        do {
            let audioFile = try AVAudioFile(forReading: fileInfo.url)
            let format = audioFile.processingFormat
            let sampleRate = format.sampleRate
            let channelCount = Int(format.channelCount)
            let durationSeconds = sampleRate > 0 ? Double(audioFile.length) / sampleRate : nil
            let bitDepth = (audioFile.fileFormat.settings[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue
            let metrics = try audioLevelMetrics(audioFile: audioFile, format: format)
            let reasons = audioQualityReasons(
                durationSeconds: durationSeconds,
                sizeBytes: fileInfo.sizeBytes,
                peak: metrics.peak,
                clippingPercent: metrics.clippingPercent,
                nearZeroPercent: metrics.nearZeroPercent,
                rms: metrics.rms
            )

            return ProjectScanFile(
                fileName: fileInfo.fileName,
                relativePath: fileInfo.relativePath,
                sizeBytes: fileInfo.sizeBytes,
                readable: true,
                readError: "",
                durationSeconds: durationSeconds,
                sampleRateHz: Int(sampleRate.rounded()),
                channels: channelCount,
                bitDepth: bitDepth,
                format: fileInfo.format,
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
                qualityFlag: reasons.isEmpty ? ProjectQuality.ok : ProjectQuality.check,
                qualityReasons: reasons
            )
        } catch {
            return ProjectScanFileFactory.unreadableFile(fileInfo, message: error.localizedDescription)
        }
    }

    /// Builds batch-level warnings from analyzed audio files.
    nonisolated func warnings(files: [ProjectScanFile], totalSizeBytes: Int) -> [String] {
        var warnings: [String] = []
        if files.isEmpty {
            warnings.append(Strings.ProjectScan.noWAVFilesFound)
        }
        if files.contains(where: { !$0.readable }) {
            warnings.append(Strings.ProjectScan.unreadableFilesFound)
        }
        if Set(files.compactMap(\.sampleRateHz)).count > 1 {
            warnings.append(Strings.ProjectScan.multipleSampleRatesFound)
        }
        if files.contains(where: { $0.qualityReasons.contains("CLIPPING_OR_NEAR_CLIPPING") || $0.qualityReasons.contains("MANY_CLIPPED_SAMPLES") }) {
            warnings.append(Strings.ProjectScan.clippedFilesFound)
        }
        if files.contains(where: { $0.qualityReasons.contains("MOSTLY_NEAR_ZERO") || $0.qualityReasons.contains("VERY_LOW_LEVEL") }) {
            warnings.append(Strings.ProjectScan.nearlyEmptyFilesFound)
        }
        if totalSizeBytes >= 10 * 1024 * 1024 * 1024 || files.count >= 500 {
            warnings.append("This batch is large and may take a while.")
        }
        return warnings
    }

    /// Reads the audio stream in chunks and calculates peak, RMS, clipping, and silence metrics.
    nonisolated private func audioLevelMetrics(audioFile: AVAudioFile, format: AVAudioFormat) throws -> AudioLevelMetrics {
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
                    if absoluteSample >= clippingThreshold { clippingCount += 1 }
                    if absoluteSample <= nearZeroThreshold { nearZeroCount += 1 }
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

    /// Converts audio metrics into persisted quality reason codes.
    nonisolated private func audioQualityReasons(
        durationSeconds: Double?,
        sizeBytes: Int,
        peak: Double,
        clippingPercent: Double,
        nearZeroPercent: Double,
        rms: Double
    ) -> [String] {
        var reasons: [String] = []
        if durationSeconds == nil || durationSeconds == 0 { reasons.append("BAD_DURATION") }
        if sizeBytes == 0 { reasons.append("EMPTY_FILE") }
        if peak >= 0.999 { reasons.append("CLIPPING_OR_NEAR_CLIPPING") }
        if clippingPercent >= 0.01 { reasons.append("MANY_CLIPPED_SAMPLES") }
        if rms <= 0.0001 { reasons.append("VERY_LOW_LEVEL") }
        if nearZeroPercent >= 95 { reasons.append("MOSTLY_NEAR_ZERO") }
        return reasons
    }

    /// Converts a normalized linear amplitude into decibels full scale.
    nonisolated private func decibelsFullScale(_ normalizedLevel: Double) -> Double {
        guard normalizedLevel > 0 else { return -120 }
        return 20 * log10(normalizedLevel)
    }
}

private struct AudioLevelMetrics: Sendable {
    /// Highest absolute sample value found in the file.
    let peak: Double
    /// Root mean square level across all sampled channels.
    let rms: Double
    /// Percentage of samples at or above the clipping threshold.
    let clippingPercent: Double
    /// Percentage of samples at or below the near-zero threshold.
    let nearZeroPercent: Double
}
