//
//  PAMScanAttributes.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation

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
        attributes.ints(PAMScanAttribute.sampleRatesHz) ?? []
    }

    nonisolated var channelCounts: [Int] {
        attributes.ints(PAMScanAttribute.channelCounts) ?? []
    }

    nonisolated var bitDepths: [Int] {
        attributes.ints(PAMScanAttribute.bitDepths) ?? []
    }
}

extension ProjectScanFile {
    nonisolated var sampleRateHz: Int? { attributes.int(PAMScanAttribute.sampleRateHz) }
    nonisolated var channels: Int? { attributes.int(PAMScanAttribute.channels) }
    nonisolated var bitDepth: Int? { attributes.int(PAMScanAttribute.bitDepth) }
    nonisolated var peakDBFS: Double? { attributes.double(PAMScanAttribute.peakDBFS) }
    nonisolated var rmsDBFS: Double? { attributes.double(PAMScanAttribute.rmsDBFS) }
    nonisolated var clippingPercent: Double? { attributes.double(PAMScanAttribute.clippingPercent) }
    nonisolated var nearZeroPercent: Double? { attributes.double(PAMScanAttribute.nearZeroPercent) }
    nonisolated var pamSourceMedia: String? { attributes.string(PAMScanAttribute.sourceMedia) }
    nonisolated var pamPreviewPath: String? { attributes.string(PAMScanAttribute.previewPath) }
    nonisolated var pamPreviewWidth: Int? { attributes.int(PAMScanAttribute.previewWidth) }
    nonisolated var pamPreviewHeight: Int? { attributes.int(PAMScanAttribute.previewHeight) }
    nonisolated var clipStartSeconds: Double? { attributes.double(PAMScanAttribute.clipStartSeconds) }
    nonisolated var clipDurationSeconds: Double? { attributes.double(PAMScanAttribute.clipDurationSeconds) }
    nonisolated var pamDetectionID: Int? { attributes.int(PAMScanAttribute.detectionID) }
    nonisolated var pamConfidence: Double? { attributes.double(PAMScanAttribute.confidence) }
    nonisolated var pamDetectionStatus: String? { attributes.string(PAMScanAttribute.status) }
}
