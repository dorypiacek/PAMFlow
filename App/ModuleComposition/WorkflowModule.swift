//
//  WorkflowModule.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation
import UI
import Core

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
            "PAM"
        case .bruvVideo:
            "BRUV"
        case .ruvImages:
            "RUV"
        }
    }

    nonisolated var libraryFolderName: String {
        switch self {
        case .pamAudio:
            "Audio"
        case .bruvVideo:
            "BRUV Video"
        case .ruvImages:
            "RUV Images"
        }
    }

    nonisolated static func module(for id: String) -> WorkflowModule {
        WorkflowModule(rawValue: id) ?? .pamAudio
    }
}
