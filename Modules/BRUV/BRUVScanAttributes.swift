//
//  BRUVScanAttributes.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import UI
import Core

/// Scan attribute keys owned by the BRUV module.
enum BRUVScanAttribute {
    nonisolated static let resolutions = "bruv.resolutions"
    nonisolated static let frameCountMin = "bruv.frame_count_min"
    nonisolated static let frameCountMax = "bruv.frame_count_max"
    nonisolated static let processingSimulated = "bruv.processing_simulated"
    nonisolated static let width = "bruv.width"
    nonisolated static let height = "bruv.height"
    nonisolated static let trackID = "bruv.track_id"
    nonisolated static let frameNumber = "bruv.frame_number"
    nonisolated static let maxN = "bruv.max_n"
    nonisolated static let confidence = "bruv.confidence"
    nonisolated static let frameCount = "bruv.frame_count"
    nonisolated static let frameRate = "bruv.frame_rate"
    nonisolated static let status = "bruv.status"
    nonisolated static let previewPath = "bruv.preview_path"
    nonisolated static let sourceMedia = "bruv.source_media"
}

extension ProjectScanSummary {
    nonisolated var resolutions: [String]? {
        attributes.strings(BRUVScanAttribute.resolutions) ?? attributes.strings("resolutions")
    }

    nonisolated var frameCountMin: Int? {
        attributes.int(BRUVScanAttribute.frameCountMin) ?? attributes.int("frame_count_min")
    }

    nonisolated var frameCountMax: Int? {
        attributes.int(BRUVScanAttribute.frameCountMax) ?? attributes.int("frame_count_max")
    }

    nonisolated var sharkTrackSimulated: Bool? {
        get { attributes.bool(BRUVScanAttribute.processingSimulated) }
        set {
            if let newValue {
                attributes[BRUVScanAttribute.processingSimulated] = .bool(newValue)
            } else {
                attributes.removeValue(forKey: BRUVScanAttribute.processingSimulated)
            }
        }
    }
}

extension ProjectScanFile {
    nonisolated var width: Int? { attributes.int(BRUVScanAttribute.width) ?? attributes.int("width") }
    nonisolated var height: Int? { attributes.int(BRUVScanAttribute.height) ?? attributes.int("height") }
    nonisolated var trackID: Int? { attributes.int(BRUVScanAttribute.trackID) ?? attributes.int("track_id") }
    nonisolated var frameNumber: Int? { attributes.int(BRUVScanAttribute.frameNumber) ?? attributes.int("frame_number") }
    nonisolated var maxN: Int? { attributes.int(BRUVScanAttribute.maxN) ?? attributes.int("max_n") }
    nonisolated var sharkTrackConfidence: Double? { attributes.double(BRUVScanAttribute.confidence) ?? attributes.double("confidence") }
    nonisolated var frameCount: Int? { attributes.int(BRUVScanAttribute.frameCount) ?? attributes.int("frame_count") }
    nonisolated var frameRate: Double? { attributes.double(BRUVScanAttribute.frameRate) ?? attributes.double("frame_rate") }
    nonisolated var sharkTrackStatus: String? { attributes.string(BRUVScanAttribute.status) ?? attributes.string("status") }
    nonisolated var sharkTrackPreviewPath: String? {
        attributes.string(BRUVScanAttribute.previewPath)
            ?? attributes.string("preview_path")
            ?? attributes.string("screenshot_path")
            ?? attributes.string("image_path")
    }
    nonisolated var sourceVideo: String? {
        attributes.string(BRUVScanAttribute.sourceMedia)
            ?? attributes.string("source_media")
            ?? attributes.string("source_video")
            ?? attributes.string("video")
    }
}
