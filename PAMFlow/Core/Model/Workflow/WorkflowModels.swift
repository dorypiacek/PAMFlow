//
//  WorkflowModels.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Module-owned file and folder names used by shared project services.
struct ModuleFileConfiguration: Hashable, Sendable {
    let sourceDirectoryName: String
    let workDirectoryName: String
    let scanSummaryFileName: String
    let generatedArtifactFolderNames: Set<String>

    init(
        sourceDirectoryName: String = ProjectFileNames.sourceDirectory,
        workDirectoryName: String = ProjectFileNames.workDirectory,
        scanSummaryFileName: String = ProjectFileNames.scanSummary,
        generatedArtifactFolderNames: Set<String> = []
    ) {
        self.sourceDirectoryName = sourceDirectoryName
        self.workDirectoryName = workDirectoryName
        self.scanSummaryFileName = scanSummaryFileName
        self.generatedArtifactFolderNames = generatedArtifactFolderNames
    }
}

/// Module-owned workflow configuration consumed by shared UI and services.
struct ModuleConfiguration {
    let details: ModuleDetails
    let fileConfiguration: ModuleFileConfiguration
    let setupConfiguration: @MainActor () -> ProjectSetupConfiguration

    init(
        details: ModuleDetails,
        fileConfiguration: ModuleFileConfiguration,
        setupConfiguration: @escaping @MainActor () -> ProjectSetupConfiguration
    ) {
        self.details = details
        self.fileConfiguration = fileConfiguration
        self.setupConfiguration = setupConfiguration
    }
}

/// Configuration consumed by the shared project setup screen.
struct ProjectSetupConfiguration {
    let module: ModuleDetails
    let usesProjectMetadata: Bool
    let metadataUploadMessage: String
    let metadataCacheKey: String
    let requiredMetadataFields: [ProjectMetadataField]
    let metadataSelectionFieldID: String?
    let isMetadataComplete: @MainActor (ProjectMetadataValues) -> Bool
    let applyMetadata: @MainActor (ProjectMetadataValues, Project) -> Void

    init(
        module: ModuleDetails,
        usesProjectMetadata: Bool = true,
        metadataUploadMessage: String,
        metadataCacheKey: String,
        requiredMetadataFields: [ProjectMetadataField],
        metadataSelectionFieldID: String? = nil,
        isMetadataComplete: @escaping @MainActor (ProjectMetadataValues) -> Bool,
        applyMetadata: @escaping @MainActor (ProjectMetadataValues, Project) -> Void
    ) {
        self.module = module
        self.usesProjectMetadata = usesProjectMetadata
        self.metadataUploadMessage = metadataUploadMessage
        self.metadataCacheKey = metadataCacheKey
        self.requiredMetadataFields = requiredMetadataFields
        self.metadataSelectionFieldID = metadataSelectionFieldID
        self.isMetadataComplete = isMetadataComplete
        self.applyMetadata = applyMetadata
    }
}

/// Metadata values captured by the shared project setup screen.
struct ProjectMetadataValues: Hashable, Sendable {
    private var valuesByFieldID: [String: String]

    init(_ valuesByFieldID: [String: String] = [:]) {
        self.valuesByFieldID = valuesByFieldID
    }

    func value(for fieldID: String) -> String {
        valuesByFieldID[fieldID] ?? ""
    }

    mutating func setValue(_ value: String, for fieldID: String) {
        valuesByFieldID[fieldID] = value
    }
}

/// Generic metadata field requested by a feature module during setup.
struct ProjectMetadataField: Hashable, Sendable {
    let id: String
    let title: String
    let isRequired: Bool
    let valueType: ProjectMetadataValueType
    let csvAliases: [String]

    init(
        id: String,
        title: String,
        isRequired: Bool,
        valueType: ProjectMetadataValueType = .string,
        csvAliases: [String] = []
    ) {
        self.id = id
        self.title = title
        self.isRequired = isRequired
        self.valueType = valueType
        self.csvAliases = csvAliases
    }
}

/// Value type used by the shared project metadata editor.
enum ProjectMetadataValueType: Hashable, Sendable {
    case string
    case number
    case date
}

/// Configuration consumed by the shared audit shell.
struct ManualAuditConfiguration: Hashable, Sendable {
    let title: String
    let emptyStateTitle: String
    let decisionOptions: [AuditDecisionOption]

    init(title: String, emptyStateTitle: String, decisionOptions: [AuditDecisionOption]) {
        self.title = title
        self.emptyStateTitle = emptyStateTitle
        self.decisionOptions = decisionOptions
    }
}

/// Generic audit decision exposed by a module.
struct AuditDecisionOption: Hashable, Sendable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Generic export field declaration for the shared CSV exporter.
struct CSVExportFieldDescriptor: Hashable, Sendable {
    let id: String
    let title: String
    let isDefault: Bool

    init(id: String, title: String, isDefault: Bool) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}
