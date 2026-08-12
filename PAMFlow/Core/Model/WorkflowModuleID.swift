//
//  WorkflowModuleID.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation

/// Stable identifiers for workflow modules supported by PAMFlow.
enum WorkflowModuleID {
    static let pamAudio = "pam_audio"
    static let bruvVideo = "bruv_video"
    static let ruvImages = "ruv_images"
}

/// Supported data-processing modules.
///
/// The selected module controls folder organization and later scan, audit, and
/// processing behavior while preserving one generic project setup flow.
enum WorkflowModule: String, CaseIterable, Identifiable, Codable, Hashable {
    case pamAudio = "pam_audio"
    case bruvVideo = "bruv_video"
    case ruvImages = "ruv_images"

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .pamAudio:
            Strings.WorkflowModule.pamTitle
        case .bruvVideo:
            Strings.WorkflowModule.bruvTitle
        case .ruvImages:
            Strings.WorkflowModule.ruvTitle
        }
    }

    nonisolated var libraryFolderName: String {
        switch self {
        case .pamAudio:
            Strings.WorkflowModule.audioFolder
        case .bruvVideo:
            Strings.WorkflowModule.bruvVideoFolder
        case .ruvImages:
            Strings.WorkflowModule.ruvImagesFolder
        }
    }

    nonisolated var usesPAMGuard: Bool {
        self == .pamAudio
    }

    nonisolated var requiresSharkTrack: Bool {
        self == .bruvVideo || self == .ruvImages
    }

    nonisolated var usesProjectMetadata: Bool {
        switch self {
        case .pamAudio, .bruvVideo, .ruvImages:
            true
        }
    }

    nonisolated static func module(for id: String) -> WorkflowModule {
        WorkflowModule(rawValue: id) ?? .pamAudio
    }
}
