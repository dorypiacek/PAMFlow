//
//  BRUVModuleConfiguration.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Configuration for visual projects, including BRUV video and RUV image workflows.
@MainActor
enum BRUVModuleConfiguration {
    static let bruvModuleID = ModuleID(rawValue: "bruv_video")
    static let ruvModuleID = ModuleID(rawValue: "ruv_images")

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
                id: bruvModuleID,
                name: BRUVStrings.Module.bruvTitle,
                subtitle: BRUVStrings.Module.bruvSubtitle,
                iconName: Icons.video,
                projectNamePrefix: "BRUV",
                libraryFolderName: BRUVStrings.Module.bruvFolderName,
                supportedFileExtensions: BRUVMediaFileExtensions.video,
                generatedArtifactFolderNames: files.generatedArtifactFolderNames
            )
        case .ruv:
            ModuleDetails(
                id: ruvModuleID,
                name: BRUVStrings.Module.ruvTitle,
                subtitle: BRUVStrings.Module.ruvSubtitle,
                iconName: Icons.image,
                projectNamePrefix: "RUV",
                libraryFolderName: BRUVStrings.Module.ruvFolderName,
                supportedFileExtensions: BRUVMediaFileExtensions.image,
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
        ProjectMetadataField(
            id: BRUVMetadataFieldID.opcode,
            title: Strings.ProjectSetup.opcode,
            isRequired: true,
            csvAliases: ["opcode", "op code", "operation code"]
        ),
        ProjectMetadataField(
            id: BRUVMetadataFieldID.date,
            title: Strings.ProjectSetup.date,
            isRequired: true, valueType: .date,
            csvAliases: ["date deployed", "deployment date", "deploy date", "sample date", "date"]
        ),
        ProjectMetadataField(
            id: BRUVMetadataFieldID.location,
            title: Strings.ProjectSetup.location,
            isRequired: true,
            csvAliases: ["location", "site", "station"]
        ),
        ProjectMetadataField(
            id: BRUVMetadataFieldID.depth,
            title: Strings.ProjectSetup.depth,
            isRequired: true,
            valueType: .number,
            csvAliases: ["depth", "water depth"]
        ),
        ProjectMetadataField(
            id: BRUVMetadataFieldID.bottomType,
            title: Strings.ProjectSetup.bottomType,
            isRequired: false,
            csvAliases: ["bottom type", "substrate", "habitat"]
        ),
        ProjectMetadataField(
            id: BRUVMetadataFieldID.waterTemperature,
            title: Strings.ProjectSetup.waterTemperature,
            isRequired: false,
            valueType: .number,
            csvAliases: ["water temperature", "temperature", "temp"]
        )
    ]

    private static func applyMetadata(_ values: ProjectMetadataValues, _ project: Project) {
        project.replaceMetadataValues(
            values.dictionary().compactMapValues { $0.trimmed.nilIfEmpty },
            summaryFieldID: BRUVMetadataFieldID.opcode
        )
    }
}

/// Visual project types served by this module.
enum BRUVProjectType: Sendable {
    case bruv
    case ruv
}

/// Metadata identifiers owned by the visual module.
enum BRUVMetadataFieldID {
    static let opcode = "opcode"
    static let date = "date"
    static let location = "location"
    static let depth = "depth"
    static let bottomType = "bottom_type"
    static let waterTemperature = "water_temperature"

    static let requiredFields = [opcode]
}

extension Project {
    var bruvMetadataOpcode: String? { metadataValue(for: BRUVMetadataFieldID.opcode) }
    var bruvMetadataDate: String? { metadataValue(for: BRUVMetadataFieldID.date) }
    var bruvMetadataLocation: String? { metadataValue(for: BRUVMetadataFieldID.location) }
    var bruvMetadataDepth: String? { metadataValue(for: BRUVMetadataFieldID.depth) }
    var bruvMetadataBottomType: String? { metadataValue(for: BRUVMetadataFieldID.bottomType) }
    var bruvMetadataWaterTemperature: String? { metadataValue(for: BRUVMetadataFieldID.waterTemperature) }
}

/// Visual module project folder and file names.
enum BRUVProjectFileNames {
    nonisolated static let detectionsDirectory = "detections"
    nonisolated static let sharkTrackInternalDirectory = "sharktrack_internal"
    nonisolated static let sharkTrackManifest = "sharktrack_manifest.json"
}

/// Visual module file extensions.
enum BRUVMediaFileExtensions {
    nonisolated static let video: Set<String> = ["mp4", "mov", "m4v", "avi"]
    nonisolated static let image: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"]
    nonisolated static let sharkTrackImage: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff"]
}
