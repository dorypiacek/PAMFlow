//
//  ProjectScanSummary.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation

/// Technical scan output used by project overview and manual audit.
nonisolated struct ProjectScanSummary: Codable, Equatable, Sendable {
    var projectName: String
    var recorderID: String?
    var inputFolder: String
    var scannedAt: Date?
    var fileCount: Int
    var readableFileCount: Int
    var unreadableFileCount: Int
    var totalSizeBytes: Int
    var durationMinSeconds: Double?
    var durationMaxSeconds: Double?
    var durationModeSeconds: Double?
    var sampleRatesHz: [Int]
    var channelCounts: [Int]
    var bitDepths: [Int]
    var formats: [String]?
    var resolutions: [String]?
    var frameCountMin: Int?
    var frameCountMax: Int?
    var qualityWarningCount: Int
    var warnings: [String]
    var files: [ProjectScanFile]
    var sharkTrackSimulated: Bool?
}

/// Technical scan output for one input file.
nonisolated struct ProjectScanFile: Codable, Equatable, Identifiable, Sendable {
    var id: String { relativePath }

    var fileName: String
    var relativePath: String
    var sizeBytes: Int
    var readable: Bool
    var readError: String
    var durationSeconds: Double?
    var sampleRateHz: Int?
    var channels: Int?
    var bitDepth: Int?
    var format: String?
    var width: Int?
    var height: Int?
    /// Stable tracker identity assigned by SharkTrack.
    var trackID: Int? = nil
    /// Zero-based or source-native frame index when emitted by SharkTrack.
    var frameNumber: Int?
    /// Maximum simultaneous count reported by SharkTrack, when available.
    var maxN: Int?
    /// Detector confidence in the normalized 0...1 range.
    var sharkTrackConfidence: Double? = nil
    var frameCount: Int?
    var frameRate: Double?
    var sharkTrackStatus: String?
    var sharkTrackPreviewPath: String?
    var sourceVideo: String? = nil
    var clipStartSeconds: Double? = nil
    var clipDurationSeconds: Double? = nil
    var peakDBFS: Double?
    var rmsDBFS: Double?
    var clippingPercent: Double?
    var nearZeroPercent: Double?
    var qualityFlag: String
    var qualityReasons: [String]
}

extension ProjectScanSummary {
    enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case recorderID = "recorder_id"
        case inputFolder = "input_folder"
        case scannedAt = "scanned_at"
        case fileCount = "file_count"
        case readableFileCount = "readable_file_count"
        case unreadableFileCount = "unreadable_file_count"
        case totalSizeBytes = "total_size_bytes"
        case durationMinSeconds = "duration_min_seconds"
        case durationMaxSeconds = "duration_max_seconds"
        case durationModeSeconds = "duration_mode_seconds"
        case sampleRatesHz = "sample_rates_hz"
        case channelCounts = "channel_counts"
        case bitDepths = "bit_depths"
        case formats
        case resolutions
        case frameCountMin = "frame_count_min"
        case frameCountMax = "frame_count_max"
        case qualityWarningCount = "quality_warning_count"
        case warnings
        case files
        case sharkTrackSimulated = "sharktrack_simulated"
    }
}

extension ProjectScanFile {
    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case relativePath = "relative_path"
        case sizeBytes = "size_bytes"
        case readable
        case readError = "read_error"
        case durationSeconds = "duration_seconds"
        case sampleRateHz = "sample_rate_hz"
        case channels
        case bitDepth = "bit_depth"
        case format
        case width
        case height
        case trackID = "track_id"
        case frameNumber = "frame_number"
        case maxN = "max_n"
        case sharkTrackConfidence = "sharktrack_confidence"
        case frameCount = "frame_count"
        case frameRate = "frame_rate"
        case sharkTrackStatus = "sharktrack_status"
        case sharkTrackPreviewPath = "sharktrack_preview_path"
        case sourceVideo = "source_video"
        case clipStartSeconds = "clip_start_seconds"
        case clipDurationSeconds = "clip_duration_seconds"
        case peakDBFS = "peak_dbfs"
        case rmsDBFS = "rms_dbfs"
        case clippingPercent = "clipping_percent"
        case nearZeroPercent = "near_zero_percent"
        case qualityFlag = "quality_flag"
        case qualityReasons = "quality_reasons"
    }
}
