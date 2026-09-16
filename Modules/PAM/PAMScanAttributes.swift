//
//  PAMScanAttributes.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import UI
import Core

/// Scan attribute keys owned by the PAM module.
enum PAMScanAttribute {
    nonisolated static let sampleRatesHz = "pam.sample_rates_hz"
    nonisolated static let channelCounts = "pam.channel_counts"
    nonisolated static let bitDepths = "pam.bit_depths"
    nonisolated static let sampleRateHz = "pam.sample_rate_hz"
    nonisolated static let channels = "pam.channels"
    nonisolated static let bitDepth = "pam.bit_depth"
    nonisolated static let peakDBFS = "pam.peak_dbfs"
    nonisolated static let rmsDBFS = "pam.rms_dbfs"
    nonisolated static let clippingPercent = "pam.clipping_percent"
    nonisolated static let nearZeroPercent = "pam.near_zero_percent"
    nonisolated static let sourceMedia = "pam.source_media"
    nonisolated static let previewPath = "pam.preview_path"
    nonisolated static let previewWidth = "pam.preview_width"
    nonisolated static let previewHeight = "pam.preview_height"
    nonisolated static let clipStartSeconds = "pam.clip_start_seconds"
    nonisolated static let clipDurationSeconds = "pam.clip_duration_seconds"
    nonisolated static let detectionID = "pam.detection_id"
    nonisolated static let confidence = "pam.confidence"
    nonisolated static let status = "pam.status"
}

extension ProjectScanSummary {
    nonisolated var sampleRatesHz: [Int] {
        attributes.ints(PAMScanAttribute.sampleRatesHz) ?? attributes.ints("sample_rates_hz") ?? []
    }

    nonisolated var channelCounts: [Int] {
        attributes.ints(PAMScanAttribute.channelCounts) ?? attributes.ints("channel_counts") ?? []
    }

    nonisolated var bitDepths: [Int] {
        attributes.ints(PAMScanAttribute.bitDepths) ?? attributes.ints("bit_depths") ?? []
    }
}

extension ProjectScanFile {
    nonisolated var sampleRateHz: Int? { attributes.int(PAMScanAttribute.sampleRateHz) ?? attributes.int("sample_rate_hz") }
    nonisolated var channels: Int? { attributes.int(PAMScanAttribute.channels) ?? attributes.int("channels") }
    nonisolated var bitDepth: Int? { attributes.int(PAMScanAttribute.bitDepth) ?? attributes.int("bit_depth") }
    nonisolated var peakDBFS: Double? { attributes.double(PAMScanAttribute.peakDBFS) ?? attributes.double("peak_dbfs") }
    nonisolated var rmsDBFS: Double? { attributes.double(PAMScanAttribute.rmsDBFS) ?? attributes.double("rms_dbfs") }
    nonisolated var clippingPercent: Double? { attributes.double(PAMScanAttribute.clippingPercent) ?? attributes.double("clipping_percent") }
    nonisolated var nearZeroPercent: Double? { attributes.double(PAMScanAttribute.nearZeroPercent) ?? attributes.double("near_zero_percent") }
    nonisolated var pamSourceMedia: String? {
        for key in [PAMScanAttribute.sourceMedia, "source_media", "source_file", "recording_file", "file", "begin_file"] {
            if let value = attributes.string(key), !value.isEmpty {
                return value
            }
        }
        for key in ["Begin File", "Source File", "Source media"] {
            if let value = legacyQualityReasonValue(key) {
                return value
            }
        }
        return nil
    }
    nonisolated var pamPreviewPath: String? {
        attributes.string(PAMScanAttribute.previewPath)
            ?? attributes.string("preview_path")
            ?? attributes.string("preview")
            ?? attributes.string("preview_image")
            ?? attributes.string("image_path")
    }
    nonisolated var pamPreviewWidth: Int? { attributes.int(PAMScanAttribute.previewWidth) ?? attributes.int("preview_width") }
    nonisolated var pamPreviewHeight: Int? { attributes.int(PAMScanAttribute.previewHeight) ?? attributes.int("preview_height") }
    nonisolated var clipStartSeconds: Double? {
        attributes.double(PAMScanAttribute.clipStartSeconds)
            ?? attributes.double("clip_start_seconds")
            ?? legacyQualityReasonValue("Begin Time (s)").flatMap(Double.init)
            ?? legacyQualityReasonValue("Start Time").flatMap(Double.init)
    }
    nonisolated var clipDurationSeconds: Double? { attributes.double(PAMScanAttribute.clipDurationSeconds) ?? attributes.double("clip_duration_seconds") }
    nonisolated var pamDetectionID: Int? { attributes.int(PAMScanAttribute.detectionID) ?? attributes.int("detection_id") }
    nonisolated var pamConfidence: Double? { attributes.double(PAMScanAttribute.confidence) ?? attributes.double("confidence") }
    nonisolated var pamDetectionStatus: String? { attributes.string(PAMScanAttribute.status) ?? attributes.string("status") }

    nonisolated private func legacyQualityReasonValue(_ key: String) -> String? {
        let prefix = "\(key):"
        return qualityReasons
            .first {
                $0.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
            }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}
