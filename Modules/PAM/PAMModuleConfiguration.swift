//
//  PAMModuleConfiguration.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import UI
import Core

/// Configuration for audio projects handled by this module.
@MainActor
enum PAMModuleConfiguration {
    static let moduleID = ModuleID(rawValue: "pam_audio")

    static let details = ModuleDetails(
        id: moduleID,
        name: PAMStrings.Module.title,
        subtitle: PAMStrings.Module.subtitle,
        iconName: Icons.audio,
        projectNamePrefix: "PAM",
        libraryFolderName: PAMStrings.Module.folderName,
        supportedFileExtensions: PAMMediaFileExtensions.audio,
        generatedArtifactFolderNames: files.generatedArtifactFolderNames
    )

    static let files = ModuleFileConfiguration(
        generatedArtifactFolderNames: [
            ProjectFileNames.sourceDirectory,
            ProjectFileNames.workDirectory,
            PAMProjectFileNames.pamguardDirectory
        ]
    )

    static func makeSetupConfiguration() -> ProjectSetupConfiguration {
        ProjectSetupConfiguration(
            module: details,
            metadataUploadMessage: PAMStrings.ProjectSetup.metadataUploadMessage,
            metadataCacheKey: "pamflow.\(details.id.rawValue).metadata.csv.bookmark",
            requiredMetadataFields: metadataFields,
            metadataSelectionFieldID: PAMMetadataFieldID.opcode,
            selectableFileExtensions: PAMMediaFileExtensions.audio,
            isMetadataComplete: { values in
                PAMMetadataFieldID.requiredFields.allSatisfy { !values.value(for: $0).trimmed.isEmpty }
            },
            applyMetadata: applyMetadata
        )
    }

    private static let metadataFields: [ProjectMetadataField] = [
        ProjectMetadataField(id: PAMMetadataFieldID.opcode, title: PAMStrings.ProjectSetup.opcode, isRequired: true, csvAliases: ["opcode", "op code", "operation code"]),
        ProjectMetadataField(id: PAMMetadataFieldID.date, title: PAMStrings.ProjectSetup.dateDeployed, isRequired: true, valueType: .date, csvAliases: ["date deployed", "deployment date", "deploy date", "sample date", "date"]),
        ProjectMetadataField(id: PAMMetadataFieldID.dateRetrieved, title: PAMStrings.ProjectSetup.dateRetrieved, isRequired: true, valueType: .date, csvAliases: ["date retrieved", "retrieval date", "retrieve date", "recovery date", "date recovered"]),
        ProjectMetadataField(id: PAMMetadataFieldID.location, title: PAMStrings.ProjectSetup.location, isRequired: true, csvAliases: ["location", "site", "station"]),
        ProjectMetadataField(id: PAMMetadataFieldID.depth, title: PAMStrings.ProjectSetup.depth, isRequired: true, valueType: .number, csvAliases: ["depth", "water depth"]),
        ProjectMetadataField(id: PAMMetadataFieldID.bottomType, title: PAMStrings.ProjectSetup.bottomType, isRequired: false, csvAliases: ["bottom type", "substrate", "habitat"])
    ]

    private static func applyMetadata(_ values: ProjectMetadataValues, _ project: Project) {
        project.replaceMetadataValues(
            values.dictionary().compactMapValues { $0.trimmed.nilIfEmpty },
            summaryFieldID: PAMMetadataFieldID.opcode
        )
    }
}

extension ProjectWorkflowStatus {
    static let pamguardSetupReady = ProjectWorkflowStatus("pamguard_setup_ready")
    static let processingProjectCreated = ProjectWorkflowStatus("processing_project_created")
    static let processingRunImported = ProjectWorkflowStatus("processing_run_imported")
    static let runOverviewCompleted = ProjectWorkflowStatus("run_overview_completed")
}

/// Metadata identifiers owned by the audio module.
enum PAMMetadataFieldID {
    static let opcode = "opcode"
    static let date = "date"
    static let dateRetrieved = "date_retrieved"
    static let location = "location"
    static let depth = "depth"
    static let bottomType = "bottom_type"

    static let requiredFields = [opcode, date, dateRetrieved, location, depth]
}

extension Project {
    var pamMetadataOpcode: String? { metadataValue(for: PAMMetadataFieldID.opcode) }
    var pamMetadataDate: String? { metadataValue(for: PAMMetadataFieldID.date) }
    var pamMetadataDateRetrieved: String? { metadataValue(for: PAMMetadataFieldID.dateRetrieved) }
    var pamMetadataLocation: String? { metadataValue(for: PAMMetadataFieldID.location) }
    var pamMetadataDepth: String? { metadataValue(for: PAMMetadataFieldID.depth) }
    var pamMetadataBottomType: String? { metadataValue(for: PAMMetadataFieldID.bottomType) }
}

/// Audio module project folder and file names.
enum PAMProjectFileNames {
    nonisolated static let pamguardDirectory = "pamguard"
    nonisolated static let pamguardDetectionsDirectory = "detections"
    nonisolated static let pamguardDatabaseDirectory = "db"
    nonisolated static let pamguardBinaryDirectory = "binary"
    nonisolated static let pamguardDetectionPreviewDirectory = "pamguard_detection_previews"
}

/// Audio module file extensions.
enum PAMMediaFileExtensions {
    nonisolated static let audio: Set<String> = ["wav", "wave"]
    nonisolated static let previewAudio: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "mp3", "m4a", "caf"]
    nonisolated static let previewImages: Set<String> = ["png", "jpg", "jpeg"]
    nonisolated static let pamguardDatabase: Set<String> = ["sqlite", "sqlite3", "db"]
    nonisolated static let pamguardBinary: Set<String> = ["pgdf", "pgnf", "pgdx"]
}

/// PAMGuard preview naming conventions used by the audio module.
enum PAMGuardPreview {
    nonisolated static let filePrefix = "event"
    nonisolated static let fileExtension = "png"
    nonisolated static let relativeEventDirectory = "\(PAMProjectFileNames.pamguardDirectory)/events"
    nonisolated static let fallbackTitle = "PAMGuard event"
    nonisolated static let eventQualityFlag = "Event"
    nonisolated static let unknownTime = "Unknown"
}

/// PAM-owned scan status values added after importing external detections.
enum PAMScanStatus {
    nonisolated static let pamguard = "pamguard"
}
