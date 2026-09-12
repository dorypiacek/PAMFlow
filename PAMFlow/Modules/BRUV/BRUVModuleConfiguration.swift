//
//  BRUVModuleConfiguration.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Module configuration for BRUV projects, including the related RUV project type.
@MainActor
enum BRUVModuleConfiguration {
    static let files = ModuleFileConfiguration(
        generatedArtifactFolderNames: [
            ProjectFileNames.sourceDirectory,
            ProjectFileNames.workDirectory,
            BRUVProjectFileNames.detectionsDirectory
        ]
    )

    static func details(for projectType: BRUVProjectType) -> ModuleDetails {
        switch projectType {
        case .bruv:
            ModuleDetails(
                id: ModuleID(rawValue: WorkflowModuleID.bruvVideo),
                name: Strings.DataTypeSelection.bruvVideoTitle,
                subtitle: Strings.DataTypeSelection.bruvVideoSubtitle,
                iconName: Icons.video,
                projectNamePrefix: "BRUV",
                libraryFolderName: Strings.WorkflowModule.bruvVideoFolder,
                supportedFileExtensions: MediaFileExtensions.video,
                generatedArtifactFolderNames: files.generatedArtifactFolderNames
            )
        case .ruv:
            ModuleDetails(
                id: ModuleID(rawValue: WorkflowModuleID.ruvImages),
                name: Strings.DataTypeSelection.ruvImageTitle,
                subtitle: Strings.DataTypeSelection.ruvImageSubtitle,
                iconName: Icons.image,
                projectNamePrefix: "RUV",
                libraryFolderName: Strings.WorkflowModule.ruvImagesFolder,
                supportedFileExtensions: MediaFileExtensions.image,
                generatedArtifactFolderNames: files.generatedArtifactFolderNames
            )
        }
    }

    static func makeSetupConfiguration(for projectType: BRUVProjectType) -> ProjectSetupConfiguration {
        let details = details(for: projectType)
        return ProjectSetupConfiguration(
            module: details,
            metadataUploadMessage: Strings.ProjectSetup.visualMetadataUploadMessage,
            metadataCacheKey: "pamflow.\(details.id.rawValue).metadata.csv.bookmark",
            requiredMetadataFields: metadataFields,
            metadataSelectionFieldID: BRUVMetadataFieldID.opcode,
            isMetadataComplete: { values in
                BRUVMetadataFieldID.requiredFields.allSatisfy { !values.value(for: $0).trimmed.isEmpty }
            },
            applyMetadata: applyMetadata
        )
    }

    private static let metadataFields: [ProjectMetadataField] = [
        ProjectMetadataField(id: BRUVMetadataFieldID.opcode, title: Strings.ProjectSetup.opcode, isRequired: true, csvAliases: ["opcode", "op code", "operation code"]),
        ProjectMetadataField(id: BRUVMetadataFieldID.date, title: Strings.ProjectSetup.date, isRequired: true, valueType: .date, csvAliases: ["date deployed", "deployment date", "deploy date", "sample date", "date"]),
        ProjectMetadataField(id: BRUVMetadataFieldID.location, title: Strings.ProjectSetup.location, isRequired: true, csvAliases: ["location", "site", "station"]),
        ProjectMetadataField(id: BRUVMetadataFieldID.depth, title: Strings.ProjectSetup.depth, isRequired: true, valueType: .number, csvAliases: ["depth", "water depth"]),
        ProjectMetadataField(id: BRUVMetadataFieldID.bottomType, title: Strings.ProjectSetup.bottomType, isRequired: false, csvAliases: ["bottom type", "substrate", "habitat"]),
        ProjectMetadataField(id: BRUVMetadataFieldID.waterTemperature, title: Strings.ProjectSetup.waterTemperature, isRequired: false, valueType: .number, csvAliases: ["water temperature", "temperature", "temp"])
    ]

    private static func applyMetadata(_ values: ProjectMetadataValues, _ project: Project) {
        project.metadataOpcode = values.value(for: BRUVMetadataFieldID.opcode).trimmed.nilIfEmpty
        project.metadataDate = values.value(for: BRUVMetadataFieldID.date).trimmed.nilIfEmpty
        project.metadataDateRetrieved = nil
        project.metadataLocation = values.value(for: BRUVMetadataFieldID.location).trimmed.nilIfEmpty
        project.metadataDepth = values.value(for: BRUVMetadataFieldID.depth).trimmed.nilIfEmpty
        project.metadataBottomType = values.value(for: BRUVMetadataFieldID.bottomType).trimmed.nilIfEmpty
        project.metadataWaterTemperature = values.value(for: BRUVMetadataFieldID.waterTemperature).trimmed.nilIfEmpty
    }
}

/// Visual project types served by the BRUV module implementation.
enum BRUVProjectType {
    case bruv
    case ruv
}

/// Metadata identifiers owned by the BRUV module.
enum BRUVMetadataFieldID {
    static let opcode = "opcode"
    static let date = "date"
    static let location = "location"
    static let depth = "depth"
    static let bottomType = "bottom_type"
    static let waterTemperature = "water_temperature"

    static let requiredFields = [opcode, date, location, depth]
}

/// BRUV module project folder and file names.
enum BRUVProjectFileNames {
    nonisolated static let detectionsDirectory = "detections"
    nonisolated static let sharkTrackInternalDirectory = "sharktrack_internal"
    nonisolated static let sharkTrackManifest = "sharktrack_manifest.json"
}

/// BRUV module file extensions.
enum BRUVMediaFileExtensions {
    nonisolated static let sharkTrackImage: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff"]
}
