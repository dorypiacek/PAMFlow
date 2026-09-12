//
//  PAMModuleConfiguration.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Module configuration for passive acoustic monitoring projects.
@MainActor
enum PAMModuleConfiguration {
    static let details = ModuleDetails(
        id: ModuleID(rawValue: WorkflowModuleID.pamAudio),
        name: Strings.DataTypeSelection.pamAudioTitle,
        subtitle: Strings.DataTypeSelection.pamAudioSubtitle,
        iconName: Icons.audio,
        projectNamePrefix: "PAM",
        libraryFolderName: Strings.WorkflowModule.audioFolder,
        supportedFileExtensions: MediaFileExtensions.wavAudio,
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
            metadataUploadMessage: Strings.ProjectSetup.pamMetadataUploadMessage,
            metadataCacheKey: "pamflow.\(details.id.rawValue).metadata.csv.bookmark",
            requiredMetadataFields: metadataFields,
            metadataSelectionFieldID: PAMMetadataFieldID.opcode,
            isMetadataComplete: { values in
                PAMMetadataFieldID.requiredFields.allSatisfy { !values.value(for: $0).trimmed.isEmpty }
            },
            applyMetadata: applyMetadata
        )
    }

    private static let metadataFields: [ProjectMetadataField] = [
        ProjectMetadataField(id: PAMMetadataFieldID.opcode, title: Strings.ProjectSetup.opcode, isRequired: true, csvAliases: ["opcode", "op code", "operation code"]),
        ProjectMetadataField(id: PAMMetadataFieldID.date, title: Strings.ProjectSetup.dateDeployed, isRequired: true, valueType: .date, csvAliases: ["date deployed", "deployment date", "deploy date", "sample date", "date"]),
        ProjectMetadataField(id: PAMMetadataFieldID.dateRetrieved, title: Strings.ProjectSetup.dateRetrieved, isRequired: true, valueType: .date, csvAliases: ["date retrieved", "retrieval date", "retrieve date", "recovery date", "date recovered"]),
        ProjectMetadataField(id: PAMMetadataFieldID.location, title: Strings.ProjectSetup.location, isRequired: true, csvAliases: ["location", "site", "station"]),
        ProjectMetadataField(id: PAMMetadataFieldID.depth, title: Strings.ProjectSetup.depth, isRequired: true, valueType: .number, csvAliases: ["depth", "water depth"]),
        ProjectMetadataField(id: PAMMetadataFieldID.bottomType, title: Strings.ProjectSetup.bottomType, isRequired: false, csvAliases: ["bottom type", "substrate", "habitat"])
    ]

    private static func applyMetadata(_ values: ProjectMetadataValues, _ project: Project) {
        project.metadataOpcode = values.value(for: PAMMetadataFieldID.opcode).trimmed.nilIfEmpty
        project.metadataDate = values.value(for: PAMMetadataFieldID.date).trimmed.nilIfEmpty
        project.metadataDateRetrieved = values.value(for: PAMMetadataFieldID.dateRetrieved).trimmed.nilIfEmpty
        project.metadataLocation = values.value(for: PAMMetadataFieldID.location).trimmed.nilIfEmpty
        project.metadataDepth = values.value(for: PAMMetadataFieldID.depth).trimmed.nilIfEmpty
        project.metadataBottomType = values.value(for: PAMMetadataFieldID.bottomType).trimmed.nilIfEmpty
        project.metadataWaterTemperature = nil
    }
}

/// Metadata identifiers owned by the PAM module.
enum PAMMetadataFieldID {
    static let opcode = "opcode"
    static let date = "date"
    static let dateRetrieved = "date_retrieved"
    static let location = "location"
    static let depth = "depth"
    static let bottomType = "bottom_type"

    static let requiredFields = [opcode, date, dateRetrieved, location, depth]
}

/// PAM-specific project folder and file names.
enum PAMProjectFileNames {
    nonisolated static let pamguardDirectory = "pamguard"
    nonisolated static let pamguardDetectionsDirectory = "detections"
    nonisolated static let pamguardDatabaseDirectory = "db"
    nonisolated static let pamguardBinaryDirectory = "binary"
    nonisolated static let pamguardDetectionPreviewDirectory = "pamguard_detection_previews"
}

/// PAM-specific file extensions.
enum PAMMediaFileExtensions {
    nonisolated static let pamguardDatabase: Set<String> = ["sqlite", "sqlite3", "db"]
    nonisolated static let pamguardBinary: Set<String> = ["pgdf", "pgnf", "pgdx"]
}

/// PAMGuard preview naming conventions used by the PAM module.
enum PAMGuardPreview {
    nonisolated static let filePrefix = "event"
    nonisolated static let fileExtension = "png"
    nonisolated static let relativeEventDirectory = "\(PAMProjectFileNames.pamguardDirectory)/events"
    nonisolated static let fallbackTitle = "PAMGuard event"
    nonisolated static let eventQualityFlag = "Event"
    nonisolated static let unknownTime = "Unknown"
}
