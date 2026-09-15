//
//  WorkflowModels.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Configuration consumed by the shared project setup screen.
public struct ProjectSetupConfiguration {
    public let module: ModuleDetails
    public let usesProjectMetadata: Bool
    public let metadataUploadMessage: String
    public let metadataCacheKey: String
    public let requiredMetadataFields: [ProjectMetadataField]
    public let metadataSelectionFieldID: String?
    public let selectableFileExtensions: Set<String>?
    public let isMetadataComplete: @MainActor (ProjectMetadataValues) -> Bool
    public let applyMetadata: @MainActor (ProjectMetadataValues, Project) -> Void

    public init(
        module: ModuleDetails,
        usesProjectMetadata: Bool = true,
        metadataUploadMessage: String,
        metadataCacheKey: String,
        requiredMetadataFields: [ProjectMetadataField],
        metadataSelectionFieldID: String? = nil,
        selectableFileExtensions: Set<String>? = nil,
        isMetadataComplete: @escaping @MainActor (ProjectMetadataValues) -> Bool,
        applyMetadata: @escaping @MainActor (ProjectMetadataValues, Project) -> Void
    ) {
        self.module = module
        self.usesProjectMetadata = usesProjectMetadata
        self.metadataUploadMessage = metadataUploadMessage
        self.metadataCacheKey = metadataCacheKey
        self.requiredMetadataFields = requiredMetadataFields
        self.metadataSelectionFieldID = metadataSelectionFieldID
        self.selectableFileExtensions = selectableFileExtensions
        self.isMetadataComplete = isMetadataComplete
        self.applyMetadata = applyMetadata
    }
}
