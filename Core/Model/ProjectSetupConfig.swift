//
//  WorkflowModels.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

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
