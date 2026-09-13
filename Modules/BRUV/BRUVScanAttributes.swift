//
//  BRUVScanAttributes.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation

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
        attributes.strings(BRUVScanAttribute.resolutions)
    }

    nonisolated var frameCountMin: Int? {
        attributes.int(BRUVScanAttribute.frameCountMin)
    }

    nonisolated var frameCountMax: Int? {
        attributes.int(BRUVScanAttribute.frameCountMax)
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
    nonisolated var width: Int? { attributes.int(BRUVScanAttribute.width) }
    nonisolated var height: Int? { attributes.int(BRUVScanAttribute.height) }
    nonisolated var trackID: Int? { attributes.int(BRUVScanAttribute.trackID) }
    nonisolated var frameNumber: Int? { attributes.int(BRUVScanAttribute.frameNumber) }
    nonisolated var maxN: Int? { attributes.int(BRUVScanAttribute.maxN) }
    nonisolated var sharkTrackConfidence: Double? { attributes.double(BRUVScanAttribute.confidence) }
    nonisolated var frameCount: Int? { attributes.int(BRUVScanAttribute.frameCount) }
    nonisolated var frameRate: Double? { attributes.double(BRUVScanAttribute.frameRate) }
    nonisolated var sharkTrackStatus: String? { attributes.string(BRUVScanAttribute.status) }
    nonisolated var sharkTrackPreviewPath: String? { attributes.string(BRUVScanAttribute.previewPath) }
    nonisolated var sourceVideo: String? { attributes.string(BRUVScanAttribute.sourceMedia) }
}
